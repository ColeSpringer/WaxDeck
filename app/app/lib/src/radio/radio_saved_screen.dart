import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'radio_saved_controller.dart';
import 'radio_saved_menu.dart';

/// Songs caught on the air and meant to be hunted down.
///
/// A playlist in shape and deliberately not in kind: nothing here is in
/// the library, so nothing here plays. What a row offers instead is the
/// search that finds it, and the removal that crosses it off - plus the
/// marker for the ones the library has since acquired, which is the
/// happy ending this list exists to reach.
class RadioSavedScreen extends ConsumerStatefulWidget {
  const RadioSavedScreen({super.key});

  @override
  ConsumerState<RadioSavedScreen> createState() => _RadioSavedScreenState();
}

class _RadioSavedScreenState extends ConsumerState<RadioSavedScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 400) return;
    ref.read(radioSavedProvider.notifier).loadMore();
  }

  Future<void> _remove(RadioSavedSong song) async {
    final l10n = context.l10n;
    try {
      await ref.read(radioSavedProvider.notifier).remove(song.pid);
    } on WaxDeckApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(radioSavedProvider);
    final rows = saved.value?.songs ?? const <RadioSavedSong>[];
    final l10n = context.l10n;

    return WaxScaffold(
      title: l10n.radioSavedTitle,
      largeTitle: false,
      controller: _scroll,
      semanticsId: SemanticsIds.radioSaved,
      onBack: () => context.leave(fallback: WaxRoute.radio),
      slivers: <Widget>[
        switch (saved) {
          AsyncData() when rows.isEmpty => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.radioSavedEmptyTitle,
              message: l10n.radioSavedEmptyMessage,
              glyph: WaxIcons.heart,
            ),
          ),
          AsyncData() => _SavedList(rows: rows, onRemove: _remove),
          AsyncError(:final error) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              title: l10n.radioSavedLoadError,
              message: context.explain(error),
              onRetry: () => ref.invalidate(radioSavedProvider),
            ),
          ),
          _ => const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.list),
          ),
        },
        if (saved.value?.loadingMore ?? false)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(WaxSpace.s16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}

class _SavedList extends ConsumerWidget {
  const _SavedList({required this.rows, required this.onRemove});

  final List<RadioSavedSong> rows;
  final Future<void> Function(RadioSavedSong song) onRemove;

  /// What a row says under its title: who it is by where the line
  /// split, where it was heard, and whether the hunt is over. In the
  /// subtitle rather than the trailing slot, which is unclipped and
  /// reserved for a timecode - a caption of this length there pushes the
  /// row's own controls off the end of it.
  static String _caption(AppLocalizations l10n, RadioSavedSong song) =>
      <String>[
        if (song.artist != null) song.artist!,
        song.stationName,
        if (song.inLibraryPid != null) l10n.radioSavedInLibrary,
      ].join(' · ');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = WaxSizeClass.of(context);
    final store = ref.watch(artworkStoreProvider);
    final repository = ref.watch(repositoryProvider);
    final l10n = context.l10n;
    return SliverPadding(
      padding: sizeClass.gutter,
      sliver: SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final song = rows[index];
          // The announced line is what the listener saw, so it is what
          // the row leads with when nothing parsed out of it.
          final title = song.title ?? song.nowPlaying;
          // Both halves or neither. The split is a pair - this server
          // sends one only when the line parsed into both - but the
          // schema makes them independently optional, and half a pair
          // interpolated would put the word "null" in a search box.
          // Falling back to the announcement is the honest answer
          // anyway: it is what the listener saw.
          final query = song.artist == null || song.title == null
              ? song.nowPlaying
              : '${song.artist} ${song.title}';
          return MediaListRow(
            data: MediaTileData(
              title: title,
              subtitle: _caption(l10n, song),
              // The snapshot taken when the heart was tapped, or the
              // monogram - which is the ordinary state rather than a
              // loading one, since most announcements have no cover on
              // any rung.
              artwork: song.hasArt
                  ? waxArtwork(store, repository.radioSavedArtUrlFor(song.pid))
                  : null,
              domain: WaxDomain.radio,
              semanticsId: SemanticsIds.radioSavedEntry(song.pid),
            ),
            // Tapping the row is the search, because finding it is the
            // whole point of the list. `go`, not `push`: a search is a
            // location a stranger can open.
            onTap: () => context.go(WaxRoute.searchFor(query)),
            // The row's own overflow, drawn by the row rather than beside
            // it, so the same sheet answers the button, a right-click,
            // and a long press instead of only the button.
            onMore: () => showRadioSavedMenu(context, ref, song),
            moreSemanticsId: SemanticsIds.radioSavedMore(song.pid),
            moreLabel: l10n.radioSavedWays(title),
            actions: <Widget>[
              WaxIconButton(
                glyph: WaxIcons.search,
                label: l10n.radioSavedFind(title),
                semanticsId: SemanticsIds.radioSavedFind(song.pid),
                onPressed: () => context.go(WaxRoute.searchFor(query)),
              ),
              WaxIconButton(
                glyph: WaxIcons.close,
                label: l10n.radioSavedForget(title),
                semanticsId: SemanticsIds.radioSavedRemove(song.pid),
                onPressed: () => onRemove(song),
              ),
            ],
          );
        },
      ),
    );
  }
}
