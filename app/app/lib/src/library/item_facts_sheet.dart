import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../music/entity_facts.dart';
import '../player/play_state_controller.dart';
import '../shell/semantics_ids.dart';

/// Everything the catalog knows about one item, as a sheet.
///
/// The read surface for the facts no screen had room for: how often the
/// caller has played it and when, the tempo the editor could write but
/// nothing could show, and the file's own technical half. Both reads are
/// ones something else may already hold - the item detail an album
/// screen asks for its chip line, the play state a star row edits - so
/// this is often warm, and it draws its own loading and error states
/// because on any row but that one it is not.
///
/// The technical rows always draw here, unlike the album's codec chip:
/// the switch that hides those governs a caption on a screen about a
/// release, and a sheet somebody opened called Details is the place the
/// answer belongs whatever the caption does.
Future<void> showItemFactsSheet(
  BuildContext context, {
  required String pid,
  required MediaType mediaType,
}) => showWaxOptionSheet(
  context,
  // Its own ref, as the item menu's sheet takes: the sheet outlives
  // the row that opened it, and a detail that arrives late redraws
  // through this rather than through a ref that may be gone.
  builder: (_) => ItemFactsSheet(pid: pid, mediaType: mediaType),
);

/// One label and its value, as the sheet draws them.
typedef _Fact = ({String key, String label, String value});

/// The sheet's body, public so a widget test can mount it without a
/// modal route.
class ItemFactsSheet extends ConsumerWidget {
  const ItemFactsSheet({required this.pid, required this.mediaType, super.key});

  final String pid;
  final MediaType mediaType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final detail = ref.watch(itemDetailProvider(pid));
    // Absent rather than zero when the state has not settled or the
    // server could not be reached: a sheet opened offline says nothing
    // about plays, where "never" would be a wrong answer rather than a
    // missing one.
    final play = ref.watch(playStateControllerProvider(pid)).value;
    // Named for the item it was raised for, as the item menu's sheet
    // is: the rows are shared ids on every surface, so a sheet opened
    // from the wrong row is otherwise indistinguishable from the right
    // one to a test.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: SemanticsIds.itemFactsSheet(pid),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: l10n.libraryFactsTitle),
          // Only as tall as the rows need, and scrolling past that: a
          // fully tagged track has thirteen rows, which on a short
          // phone is taller than a sheet may be.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // The listening record is the catalog's rather than
                  // the file's, so it draws beside a detail that is
                  // still arriving and beside one that never will.
                  _Rows(rows: _playFacts(l10n, play)),
                  switch (detail) {
                    AsyncData(:final value) => _Rows(
                      rows: _fileFacts(l10n, value),
                    ),
                    AsyncError(:final error) => Padding(
                      padding: const EdgeInsets.all(WaxSpace.s16),
                      child: ErrorState(
                        message: context.explain(error),
                        onRetry: () => ref.invalidate(itemDetailProvider(pid)),
                        semanticsId: SemanticsIds.itemFactsError,
                      ),
                    ),
                    _ => const Padding(
                      padding: EdgeInsets.all(WaxSpace.s16),
                      child: SkeletonShapes(shape: SkeletonShape.list),
                    ),
                  },
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What the caller has done with this item. Empty when the play state
  /// has not settled or could not be read.
  List<_Fact> _playFacts(AppLocalizations l10n, PlayState? play) => <_Fact>[
    if (play != null) ...<_Fact>[
      (
        key: 'plays',
        label: l10n.libraryFactsPlayCount,
        value: '${play.playCount}',
      ),
      (
        key: 'last-played',
        label: l10n.libraryFactsLastPlayed,
        value: _lastPlayed(l10n, play),
      ),
    ],
  ];

  /// What the file and its tags are, in the order a reader looks for
  /// them: what it sounds like, then when it is from, then what it is
  /// made of, then the identifiers nothing else shows.
  List<_Fact> _fileFacts(AppLocalizations l10n, ItemDetail detail) => <_Fact>[
    if (mediaType == MediaType.music && (detail.bpm ?? 0) > 0)
      (
        key: 'bpm',
        label: l10n.libraryFactsBpm,
        value: l10n.formatTempo(detail.bpm!),
      ),
    if (detail.durationMs > 0)
      (
        key: 'duration',
        label: l10n.libraryFactsDuration,
        value: formatTimecode(Duration(milliseconds: detail.durationMs)),
      ),
    if (detail.year != null)
      (key: 'year', label: l10n.libraryFactsYear, value: '${detail.year}'),
    if (detail.genres.isNotEmpty)
      (
        key: 'genres',
        label: l10n.libraryFactsGenres,
        value: detail.genres.join(', '),
      ),
    if ((detail.codec ?? '').isNotEmpty)
      (
        key: 'codec',
        label: l10n.libraryFactsCodec,
        value: detail.codec!.toUpperCase(),
      ),
    if ((detail.container ?? '').isNotEmpty)
      (
        key: 'container',
        label: l10n.libraryFactsContainer,
        value: detail.container!.toUpperCase(),
      ),
    if ((detail.sampleRate ?? 0) > 0)
      (
        key: 'sample-rate',
        label: l10n.libraryFactsSampleRate,
        value: l10n.formatSampleRate(detail.sampleRate!),
      ),
    if ((detail.bitrate ?? 0) > 0)
      (
        key: 'bitrate',
        label: l10n.libraryFactsBitrate,
        value: l10n.formatBitrate(detail.bitrate!),
      ),
    if (detail.addedAt != null)
      (
        key: 'added',
        label: l10n.libraryFactsAdded,
        value: l10n.formatDate(detail.addedAt!.toLocal()),
      ),
    if ((detail.mbid ?? '').isNotEmpty)
      (key: 'mbid', label: l10n.libraryFactsMbid, value: detail.mbid!),
    if ((detail.isrc ?? '').isNotEmpty)
      (key: 'isrc', label: l10n.libraryFactsIsrc, value: detail.isrc!),
  ];

  /// When the last play was counted.
  ///
  /// Three readings, not two. A hand mark - the button that clears a
  /// backlog somebody heard elsewhere - raises the count without
  /// claiming a time, so a played item can carry no stamp: that is
  /// unknown, and "never" beside a count of one is a contradiction the
  /// reader would have to resolve.
  ///
  /// Relative, but the compact scale rather than the spaced one, which
  /// stops at days: a track last played two years ago is an ordinary
  /// row here, and "730 d ago" is arithmetic homework.
  String _lastPlayed(AppLocalizations l10n, PlayState play) {
    final at = play.lastPlayedAt;
    if (at != null) return l10n.relativeCompact(at);
    return play.playCount > 0
        ? l10n.libraryFactsLastPlayedUnknown
        : l10n.libraryFactsNeverPlayed;
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.rows});

  final List<_Fact> rows;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final row in rows)
        MonoDetailRow(
          label: row.label,
          value: row.value,
          semanticsId: SemanticsIds.itemFactsRow(row.key),
        ),
    ],
  );
}
