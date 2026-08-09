import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../uploads/add_to_library.dart';

/// The ways off a saved-radio row into getting the song: hand it to
/// Add-from-URL, or hand its name to a pending review entry's own
/// identify search. Both surfaces existed before this menu; the menu is
/// the caller they were missing.
Future<void> showRadioSavedMenu(
  BuildContext context,
  WidgetRef ref,
  RadioSavedSong song,
) async {
  final colors = WaxColors.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: colors.surface2,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WaxSpace.s16,
          0,
          WaxSpace.s16,
          WaxSpace.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: song.title ?? song.nowPlaying,
              overline: 'Heard on ${song.stationName}',
            ),
            WaxOptionRow(
              title: 'Get it from a URL',
              subtitle: 'Download a copy you found; it lands in review',
              glyph: WaxIcons.downloads,
              semanticsId: SemanticsIds.radioSavedAcquire,
              onTap: () => Navigator.of(sheetContext).pop('acquire'),
            ),
            WaxOptionRow(
              title: 'Identify a review entry as it',
              subtitle: "Hand its name to a pending entry's search",
              glyph: WaxIcons.search,
              semanticsId: SemanticsIds.radioSavedIdentify,
              onTap: () => Navigator.of(sheetContext).pop('identify'),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'acquire':
      await acquireFromUrl(context, ref, initial: MediaType.music);
    case 'identify':
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: colors.surface2,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => RadioSavedIdentifySheet(song: song),
      );
  }
}

/// Picks a pending one-track music entry from the review queue and
/// re-identifies it with the radio announcement's own read, which is
/// often cleaner than what a downloaded file's title parsed into. The
/// queue listing is already per-caller (administrators see everything,
/// everybody else their own uploads), so the sheet needs no gate.
class RadioSavedIdentifySheet extends ConsumerStatefulWidget {
  const RadioSavedIdentifySheet({required this.song, super.key});

  final RadioSavedSong song;

  @override
  ConsumerState<RadioSavedIdentifySheet> createState() =>
      _RadioSavedIdentifySheetState();
}

class _RadioSavedIdentifySheetState
    extends ConsumerState<RadioSavedIdentifySheet> {
  /// Null while the probe is out, then the pending one-track music
  /// entries: the shape a radio song can honestly name. An album-sized
  /// unit identified as one song would be a wrong answer offered
  /// confidently.
  List<ReviewEntry>? _entries;
  Object? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
  }

  Future<void> _probe() async {
    try {
      final page = await ref
          .read(repositoryProvider)
          .listReviewQueue(status: 'pending', limit: 50);
      if (!mounted) return;
      setState(
        () => _entries = <ReviewEntry>[
          for (final entry in page.entries)
            if (entry.mediaType == MediaType.music && entry.trackCount == 1)
              entry,
        ],
      );
    } on WaxDeckApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _identify(ReviewEntry entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final messenger = ref.read(shellMessengerProvider.notifier);
    final song = widget.song;
    try {
      // Both halves or neither, the list's own rule: half a parsed pair
      // would search for the word "null". The announced line is the
      // honest fallback - it is what the listener saved.
      if (song.artist == null || song.title == null) {
        await ref
            .read(repositoryProvider)
            .reidentifyReviewEntry(entry.id, title: song.nowPlaying);
      } else {
        await ref
            .read(repositoryProvider)
            .reidentifyReviewEntry(
              entry.id,
              artist: song.artist,
              title: song.title,
            );
      }
      if (mounted) navigator.pop();
      // Onto the entry itself, where the candidates the search finds
      // land and the decision is made.
      unawaited(router.push<void>(WaxRoute.reviewEntry(entry.id)));
    } on WaxDeckApiException catch (e) {
      messenger.show(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final entries = _entries;
    final song = widget.song;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WaxSpace.s16,
          0,
          WaxSpace.s16,
          WaxSpace.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SectionHeader(
              title: 'Identify as "${song.title ?? song.nowPlaying}"',
              overline: 'Pending single tracks in the review queue',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
                child: Text(
                  'Could not load the review queue.',
                  style: WaxType.bodySmall.copyWith(color: colors.error),
                ),
              )
            else if (entries == null)
              const Padding(
                padding: EdgeInsets.all(WaxSpace.s16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
                child: Text(
                  'No pending single tracks to name. Get the song from a '
                  'URL first and it turns up here while it waits for '
                  'review.',
                  style: WaxType.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return WaxOptionRow(
                      title: entry.title ?? 'Untitled',
                      subtitle: entry.artist,
                      glyph: WaxIcons.music,
                      semanticsId: SemanticsIds.radioSavedIdentifyEntry(
                        entry.id,
                      ),
                      onTap: _busy ? null : () => unawaited(_identify(entry)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
