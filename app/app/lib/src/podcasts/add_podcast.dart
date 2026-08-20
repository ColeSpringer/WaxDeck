import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import 'podcasts_controller.dart';

/// Subscribes to a directory match, saying so where the caller cannot.
///
/// Answers null on success, or the server's message when it refused. The
/// same split radio's `addDirectoryStation` makes, for the same reason:
/// where a refusal belongs depends on the caller. On the search screen a
/// snackbar is right. Inside the add dialog it is not, because a snackbar
/// renders on the scaffold *behind* the modal route.
Future<String?> subscribeToDirectoryEntry(
  BuildContext context,
  WidgetRef ref,
  PodcastDirectoryEntry entry,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    // A directory match is always an RSS feed, so no source kind is asked
    // for or sent: the whole reason the endpoint returns `feedUrl` is
    // that the answer is already known. Through the controller rather
    // than the repository, so the hub's grid holds the new show without
    // being told about it separately.
    await ref
        .read(subscriptionsProvider.notifier)
        .subscribe(url: entry.feedUrl);
    // Safe from the dialog too: it pops on success, so the message is
    // uncovered by the time it matters. Checked because the messenger
    // was captured before the await and a subscribe outlives the screen
    // that started it: showing on a torn-down one throws.
    if (messenger.mounted) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.searchSubscribed(entry.name))),
        );
    }
    return null;
  } on WaxDeckApiException catch (e) {
    // The feed URL came off the directory rather than out of a field, so
    // nothing anybody typed is what was refused: the table's own sentence
    // is the right one.
    return explainError(l10n, e);
  }
}

/// One directory match: what the show is, and the one thing to do with it.
///
/// Shared, because the directory is drawn in two places - this dialog and
/// search's Podcasts scope - and somebody choosing between six shows that
/// share a word in their titles should be reading the same row in both.
class PodcastDirectoryRow extends StatelessWidget {
  const PodcastDirectoryRow({
    required this.entry,
    required this.index,
    required this.onSubscribe,
    this.rowSemanticsId,
    super.key,
  });

  final PodcastDirectoryEntry entry;

  /// Where the row sits in the results, which is what the subscribe
  /// button's identifier is built from.
  final int index;

  /// Null disables the button, for a surface already busy with one.
  final VoidCallback? onSubscribe;

  /// The row's own identifier, where the surface has one for it. The
  /// button keeps its own either way, being a control beside the row
  /// rather than inside it.
  final String? rowSemanticsId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return WaxOptionRow(
      title: entry.name,
      subtitle: describePodcastDirectoryEntry(l10n, entry),
      glyph: WaxIcons.podcasts,
      semanticsId: rowSemanticsId,
      trailing: WaxButton(
        label: l10n.searchSubscribe,
        kind: WaxButtonKind.tonal,
        icon: WaxIcons.add,
        semanticsId: SemanticsIds.podcastSearchSubscribe(index),
        onPressed: onSubscribe,
      ),
    );
  }
}

/// Adding a show, starting from its name.
///
/// The directory search is the primary input, because a name is what
/// somebody adding a podcast has. Pasting a feed URL is the expert path -
/// a YouTube channel and a private feed have no directory entry and must
/// stay reachable - so it keeps every field it had, behind a disclosure.
///
/// The search runs here rather than through
/// `podcastDirectoryResultsProvider`, which is scoped to the search
/// screen's own query and chip.
class SubscribeDialog extends ConsumerStatefulWidget {
  const SubscribeDialog({super.key});

  @override
  ConsumerState<SubscribeDialog> createState() => _SubscribeDialogState();
}

class _SubscribeDialogState extends ConsumerState<SubscribeDialog> {
  final _searchController = TextEditingController();
  final _urlController = TextEditingController();

  /// The URL field's own focus, moved to by hand when the disclosure
  /// opens. `autofocus` cannot do it: Flutter applies one only while its
  /// scope has no focused child, and the search field above took that on
  /// the way in - so the field would look live while every keystroke
  /// went on landing in the search box.
  final _urlFocus = FocusNode();
  var _sourceType = 'rss';
  var _busy = false;

  /// Whether the URL path is showing. Opened by hand, or by a directory
  /// that will not answer - there being nothing else left to try.
  var _byUrl = false;

  /// Null until a search has run, which is what tells "nothing looked
  /// for" from "nothing found".
  List<PodcastDirectoryEntry>? _matches;

  /// What the dialog is reporting, from a search or from a subscribe.
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    _urlController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  /// Opens or closes the URL path, taking the caret with it on the way
  /// open. After the frame, because the field is not mounted until the
  /// rebuild this schedules has run.
  void _toggleByUrl() {
    setState(() => _byUrl = !_byUrl);
    if (!_byUrl) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _byUrl) _urlFocus.requestFocus();
    });
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    // Anything at all, rather than a two-character minimum: a
    // single-character title is a whole word in Chinese or Japanese, and
    // a run button that answers a real query by doing nothing at all -
    // no spinner, no rows, no sentence - reads as broken.
    if (query.isEmpty || _busy) return;
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await ref
          .read(repositoryProvider)
          .searchPodcastDirectory(query, limit: 15);
      if (mounted) setState(() => _matches = results);
    } on WaxDeckApiException catch (e) {
      if (mounted) {
        setState(() {
          // The way out, said with the failure that implies it - and
          // opened, because a directory that will not answer leaves the
          // feed URL as the only way through.
          _error = l10n.podcastSearchFailedHint(explainError(l10n, e));
          _byUrl = true;
          // The rows an earlier search found are not an answer to this
          // one, and left above "could not search" they read as one.
          _matches = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _subscribeToEntry(PodcastDirectoryEntry entry) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    var popped = false;
    try {
      final refusal = await subscribeToDirectoryEntry(context, ref, entry);
      if (refusal == null) {
        // Only while this dialog is still up: a subscribe outlives a
        // dialog dismissed while it was in flight, and popping a
        // captured navigator then takes whatever is on top instead.
        if (mounted) {
          navigator.pop();
          popped = true;
        }
        return;
      }
      if (mounted) setState(() => _error = refusal);
    } finally {
      // Every other async path here clears the flag in a finally, and
      // this one is the path that can throw something no caller
      // converts - a decode failure, a reload rethrown by
      // `invalidateSelf`. Left set, every control in the dialog reads as
      // disabled and only Cancel works.
      if (mounted && !popped) setState(() => _busy = false);
    }
  }

  Future<void> _subscribeToUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    try {
      await ref
          .read(subscriptionsProvider.notifier)
          .subscribe(url: url, sourceType: _sourceType);
      if (mounted) navigator.pop();
    } on WaxDeckApiException catch (e) {
      // Inline rather than a snackbar, which would render behind this
      // dialog. The URL was just typed, so the server's own words about
      // it: "the feed's own server did not answer" names the address.
      if (mounted) setState(() => _error = explainRefusal(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = WaxColors.of(context);
    return AlertDialog(
      title: Text(l10n.podcastAddSubscription),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The house search field rather than a labelled one: this
              // asks what to look for, and the rows under it are what it
              // found.
              SearchField(
                label: l10n.podcastSearchDirectory,
                hint: l10n.podcastShowName,
                controller: _searchController,
                autofocus: true,
                onSubmitted: (_) => unawaited(_runSearch()),
                semanticsId: SemanticsIds.podcastSearchField,
              ),
              const SizedBox(height: WaxSpace.s8),
              WaxButton(
                label: l10n.podcastSearchDirectory,
                kind: WaxButtonKind.tonal,
                icon: WaxIcons.search,
                semanticsId: SemanticsIds.podcastSearchRun,
                onPressed: _busy ? null : () => unawaited(_runSearch()),
              ),
              ..._resultList(l10n),
              const SizedBox(height: WaxSpace.s8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: WaxButton(
                  label: l10n.podcastAddByUrl,
                  kind: WaxButtonKind.inline,
                  // Matching every other disclosure in the app: open
                  // shows the caret that closes it.
                  icon: _byUrl ? WaxIcons.collapse : WaxIcons.expand,
                  semanticsId: SemanticsIds.podcastAddByUrl,
                  onPressed: _toggleByUrl,
                ),
              ),
              if (_byUrl) ..._urlForm(l10n),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: WaxSpace.s8),
                  child: Text(
                    _error!,
                    style: WaxType.caption.copyWith(color: colors.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        WaxButton(
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        // The directory rows subscribe themselves, so a confirm button
        // belongs to the URL path alone.
        if (_byUrl)
          WaxButton(
            label: l10n.podcastSubscribeAction,
            semanticsId: SemanticsIds.podcastSubscribeConfirm,
            onPressed: _busy ? null : () => unawaited(_subscribeToUrl()),
          ),
      ],
    );
  }

  /// Directory matches, bounded so a long list scrolls inside the dialog
  /// rather than growing it past the window.
  List<Widget> _resultList(AppLocalizations l10n) {
    final matches = _matches;
    if (matches == null) return const <Widget>[];
    if (matches.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.all(WaxSpace.s12),
          child: Text(l10n.podcastNoMatches),
        ),
      ];
    }
    return <Widget>[
      const SizedBox(height: WaxSpace.s8),
      SectionHeader(
        overline: l10n.searchDirectoryOverline,
        title: l10n.searchShowsToSubscribe,
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: matches.length,
          itemBuilder: (context, index) => PodcastDirectoryRow(
            entry: matches[index],
            index: index,
            onSubscribe: _busy
                ? null
                : () => unawaited(_subscribeToEntry(matches[index])),
          ),
        ),
      ),
    ];
  }

  /// The expert path, unchanged: one URL and the kind of source it is.
  List<Widget> _urlForm(AppLocalizations l10n) => <Widget>[
    const SizedBox(height: WaxSpace.s8),
    // No Semantics identifier wrapper: on the web it would mint a
    // second, disabled text-field node beside the real input. Tests
    // locate the field by its label, like the login form.
    TextField(
      key: const Key('podcast-url-field'),
      controller: _urlController,
      focusNode: _urlFocus,
      decoration: InputDecoration(labelText: l10n.podcastFeedUrlLabel),
      keyboardType: TextInputType.url,
    ),
    const SizedBox(height: WaxSpace.s12),
    WaxSegmented(
      label: l10n.podcastSourceLabel,
      segments: <WaxSegment>[
        WaxSegment(name: 'rss', label: l10n.podcastSourceRss),
        WaxSegment(name: 'youtube', label: l10n.podcastSourceYouTube),
      ],
      selected: _sourceType,
      onSelect: (name) => setState(() => _sourceType = name),
    ),
  ];
}
