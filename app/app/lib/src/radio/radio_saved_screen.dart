import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
import '../l10n/l10n.dart';
import '../presenters/media_tiles.dart';
import '../providers.dart';
import '../shell/async_sliver_face.dart';
import '../shell/paged_scroll.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
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

class _RadioSavedScreenState extends ConsumerState<RadioSavedScreen>
    with PagedScroll {
  @override
  void loadMore() => ref.read(radioSavedProvider.notifier).loadMore();

  Future<void> _remove(RadioSavedSong song) async {
    final l10n = context.l10n;
    try {
      await ref.read(radioSavedProvider.notifier).remove(song.pid);
    } on WaxDeckApiException catch (e) {
      if (!mounted) return;
      ref
          .read(shellMessengerProvider.notifier)
          .show(explainError(l10n, e), channel: ShellChannel.radio);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(radioSavedProvider);
    fillViewportWhile(
      (saved.value?.hasMore ?? false) && !(saved.value?.loadingMore ?? true),
      at: saved.value?.songs,
    );
    final l10n = context.l10n;

    return WaxScaffold(
      title: l10n.radioSavedTitle,
      largeTitle: false,
      controller: pagedScroll,
      semanticsId: SemanticsIds.radioSaved,
      onBack: () => context.leave(fallback: WaxRoute.radio),
      slivers: <Widget>[
        AsyncSliverFace<RadioSavedState>(
          state: saved,
          errorTitle: l10n.radioSavedLoadError,
          onRetry: () => ref.invalidate(radioSavedProvider),
          isEmpty: (value) => value.songs.isEmpty,
          empty: (context, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.radioSavedEmptyTitle,
              message: l10n.radioSavedEmptyMessage,
              glyph: WaxIcons.heart,
            ),
          ),
          builder: (context, value) =>
              _SavedList(rows: value.songs, onRemove: _remove),
        ),
        if (saved.value?.loadingMore ?? false)
          const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.list, count: 1),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: WaxSpace.s32)),
      ],
    );
  }
}

/// A row's key, so the row moves with its song (see [indexByKey]).
Key _songKey(RadioSavedSong song) =>
    ValueKey(SemanticsIds.radioSavedEntry(song.pid));

class _SavedList extends ConsumerWidget {
  const _SavedList({required this.rows, required this.onRemove});

  final List<RadioSavedSong> rows;
  final Future<void> Function(RadioSavedSong song) onRemove;

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
        findChildIndexCallback: indexByKey(rows, _songKey),
        itemBuilder: (context, index) {
          final song = rows[index];
          final tile = savedSongTile(
            song,
            l10n: l10n,
            store: store,
            repository: repository,
            semanticsId: SemanticsIds.radioSavedEntry(song.pid),
          );
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
            key: _songKey(song),
            data: tile,
            // Tapping the row is the search, because finding it is the
            // whole point of the list. `go`, not `push`: a search is a
            // location a stranger can open.
            onTap: () => context.go(WaxRoute.searchFor(query)),
            // The row's own overflow, drawn by the row rather than beside
            // it, so the same sheet answers the button, a right-click,
            // and a long press instead of only the button.
            onMore: () => showRadioSavedMenu(context, ref, song),
            moreSemanticsId: SemanticsIds.radioSavedMore(song.pid),
            moreLabel: l10n.radioSavedWays(tile.title),
            actions: <Widget>[
              WaxIconButton(
                glyph: WaxIcons.search,
                label: l10n.radioSavedFind(tile.title),
                semanticsId: SemanticsIds.radioSavedFind(song.pid),
                onPressed: () => context.go(WaxRoute.searchFor(query)),
              ),
              WaxIconButton(
                glyph: WaxIcons.close,
                label: l10n.radioSavedForget(tile.title),
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
