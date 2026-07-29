import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'podcast_shelves.dart';
import 'podcasts_controller.dart';

/// How far back "older" reaches.
enum MarkOlderPreset {
  month('month', 'Older than a month', Duration(days: 30)),
  week('week', 'Older than a week', Duration(days: 7)),
  everything('all', 'Every episode', null);

  const MarkOlderPreset(this.name, this.label, this.age);

  final String name;
  final String label;

  /// How old an episode has to be. Null takes the whole backlog.
  final Duration? age;

  /// The newest publication time this preset admits, against [now].
  DateTime? cutoff(DateTime now) => age == null ? null : now.subtract(age!);
}

/// Marks a show's backlog as played.
///
/// The four-hundred-episode problem on a new subscription: a listener
/// follows a show for the current episode and inherits a decade of unread
/// dots. There is no bulk endpoint for this and there should not be
/// one: played is derived from the position reached, so saying it means
/// checkpointing each episode at its own duration. That is one request
/// per episode, which is why this is a dialog with a progress bar rather
/// than a menu item that appears to do nothing for a minute.
class MarkOlderPlayedDialog extends ConsumerStatefulWidget {
  const MarkOlderPlayedDialog({super.key, required this.pid});

  final String pid;

  @override
  ConsumerState<MarkOlderPlayedDialog> createState() =>
      _MarkOlderPlayedDialogState();
}

class _MarkOlderPlayedDialogState extends ConsumerState<MarkOlderPlayedDialog> {
  var _preset = MarkOlderPreset.month;
  var _running = false;
  var _done = 0;
  var _total = 0;

  /// Set when the visitor closes the dialog mid-run, so the loop stops
  /// at the next episode rather than writing through a screen nobody is
  /// looking at.
  var _cancelled = false;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  /// Every episode of the show, oldest first, so a run interrupted
  /// halfway has cleared the oldest dots rather than a random scatter.
  ///
  /// Read straight from the repository rather than from the screen's
  /// listing: the listing holds the pages that were scrolled, and the
  /// backlog this exists for is exactly the part nobody scrolled to.
  Future<List<EpisodeSummary>> _backlog(DateTime? cutoff) async {
    final repository = ref.read(repositoryProvider);
    final episodes = <EpisodeSummary>[];
    String? cursor;
    do {
      final page = await repository.listEpisodes(
        widget.pid,
        cursor: cursor,
        limit: 200,
      );
      for (final episode in page.items) {
        if (cutoff != null && !episode.publishedAt.isBefore(cutoff)) continue;
        // A feed that declared no duration leaves no position that means
        // finished, so there is nothing to write for it.
        if (episode.durationMs <= 0) continue;
        episodes.add(episode);
      }
      cursor = page.nextCursor;
    } while (cursor != null && !_cancelled);
    return episodes.reversed.toList();
  }

  /// How many checkpoints ride at once.
  ///
  /// Sequential was thirty seconds of staring at a bar for a
  /// three-hundred-episode backlog on a phone: each write is its own
  /// round trip, and latency, not the server, is the whole cost. Six is
  /// enough to hide that without turning a housekeeping chore into a
  /// burst nobody asked for. It costs a little of the oldest-first
  /// guarantee (a stopped run can leave up to a batch ragged at the
  /// boundary), which is a far smaller lie than the random scatter an
  /// unbounded fan-out would leave.
  static const _batch = 6;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _done = 0;
      _total = 0;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // The container rather than `ref`: this loop outlives the dialog
    // whenever the visitor stops it or walks away, and what it has
    // already written has to reach the screens underneath either way.
    // `ref` is dead the moment this State is disposed; the container is
    // not.
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = container.read(repositoryProvider);
    var done = 0;
    String? failure;
    // The backlog walk is a paged read and can fail like any other.
    // Uncaught it escaped as an unhandled async error and left the
    // dialog running forever: a bar that never moved and a confirm
    // button that never came back. Nothing has been written at this
    // point, so a failure here has nothing to invalidate and its own
    // way out.
    final List<EpisodeSummary> episodes;
    try {
      episodes = await _backlog(_preset.cutoff(DateTime.now()));
    } on WaxDeckApiException catch (e) {
      if (_cancelled || !mounted) return;
      setState(() => _running = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not read the backlog: ${e.message}')),
        );
      return;
    }
    if (mounted) setState(() => _total = episodes.length);

    try {
      for (var at = 0; at < episodes.length && !_cancelled; at += _batch) {
        final end = (at + _batch).clamp(0, episodes.length);
        final outcomes = await Future.wait(<Future<String?>>[
          for (final episode in episodes.sublist(at, end))
            _checkpoint(repository, episode),
        ]);
        for (final outcome in outcomes) {
          if (outcome == null) {
            done++;
          } else {
            failure ??= outcome;
          }
        }
        if (mounted) setState(() => _done = done);
        if (failure != null) break;
      }
    } finally {
      // Whatever landed, landed: the listing and every position beside
      // it are stale whether or not anybody is still looking at this
      // dialog. The whole progress family rather than one key, since
      // those reads are keyed by the rows a surface happens to hold and
      // this wrote past all of them.
      if (done > 0) {
        container.invalidate(episodesProvider(widget.pid));
        container.invalidate(episodeProgressProvider);
        // The hub's tile draws the show's unplayed backlog, which is
        // exactly the number this just changed, and it comes from the
        // subscription row rather than from anything the show screen
        // holds.
        container.invalidate(subscriptionsProvider);
        container.invalidate(upNextEpisodesProvider);
        container.invalidate(latestEpisodesProvider);
      }
    }

    // Stopping already dismissed this dialog, and popping again from
    // here would take the screen underneath with it.
    //
    // Guarded on the flag rather than on `mounted`, which is not the
    // same question: a pop begins a route transition, so the State is
    // still mounted for the length of the dismissal animation, and a
    // checkpoint landing inside that window would find `mounted` true
    // and pop the show screen. `_cancelled` is set by the Stop button
    // and by dispose, and both mean the same thing here: this dialog
    // is on its way out and is nobody's to close a second time.
    if (_cancelled || !mounted) return;
    if (failure != null) {
      setState(() => _running = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Stopped after $done: $failure')),
        );
      return;
    }
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$done ${done == 1 ? 'episode' : 'episodes'} marked as played',
          ),
        ),
      );
  }

  /// One checkpoint: null when it landed, the server's message when it
  /// did not. Failures are values rather than throws so one refusal
  /// inside a batch cannot take its siblings' outcomes with it.
  Future<String?> _checkpoint(
    WaxDeckRepository repository,
    EpisodeSummary episode,
  ) async {
    try {
      await repository.putPlayState(episode.pid, episode.durationMs);
      return null;
    } on WaxDeckApiException catch (e) {
      return e.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return AlertDialog(
      title: const Text('Mark older episodes as played'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Clears the unplayed dots on a backlog. Your positions on '
            'episodes you actually started are overwritten, and nothing is '
            'deleted.',
            style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: WaxSpace.s16),
          RadioGroup<MarkOlderPreset>(
            groupValue: _preset,
            onChanged: (chosen) {
              if (_running) return;
              setState(() => _preset = chosen ?? _preset);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final preset in MarkOlderPreset.values)
                  Semantics(
                    identifier: SemanticsIds.markOlderPreset(preset.name),
                    child: RadioListTile<MarkOlderPreset>(
                      key: Key(SemanticsIds.markOlderPreset(preset.name)),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: preset,
                      title: Text(preset.label),
                    ),
                  ),
              ],
            ),
          ),
          if (_running) ...<Widget>[
            const SizedBox(height: WaxSpace.s16),
            LinearProgressIndicator(
              // Indeterminate while the backlog is still being counted:
              // a bar sitting at zero over an unknown total reads as
              // stalled, and the count is a page-walk of its own.
              value: _total == 0 ? null : _done / _total,
            ),
            const SizedBox(height: WaxSpace.s8),
            Text(
              _total == 0 ? 'Reading the backlog...' : '$_done of $_total',
              style: WaxType.monoData.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        WaxButton(
          label: _running ? 'Stop' : 'Cancel',
          kind: WaxButtonKind.text,
          onPressed: () {
            _cancelled = true;
            Navigator.of(context).pop();
          },
        ),
        WaxButton(
          label: 'Mark played',
          semanticsId: SemanticsIds.markOlderConfirm,
          onPressed: _running ? null : _run,
        ),
      ],
    );
  }
}
