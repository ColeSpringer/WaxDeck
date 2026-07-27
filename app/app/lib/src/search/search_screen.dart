import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../music/music_controllers.dart';
import '../player/now_playing_controller.dart';
import '../queue/queue_state.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'search_controller.dart';

/// One search over everything the caller can see.
///
/// The query is in the URL, so a result set is a link and a reload lands
/// back on it; the field, the chips, and the groups are all views of the
/// one query this screen owns.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({this.initialQuery = '', super.key});

  /// The `q` the location arrived with.
  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initialQuery,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'search-field');

  /// Groups the visitor has expanded past the first few hits.
  final Set<SearchHitKind> _expanded = <SearchHitKind>{};

  @override
  void initState() {
    super.initState();
    _adopt(widget.initialQuery);
  }

  @override
  void didUpdateWidget(SearchScreen old) {
    super.didUpdateWidget(old);
    // Arriving at `/search` while already on `/search?q=night` is one
    // click — the sidebar launcher is on screen the whole time, and so
    // is every rebuilt screen's search control. go_router keys a page by
    // its path and its path parameters, and a query is neither, so the
    // same State is reused and `initState` never runs again. Without
    // this the field still reads "night", the results are still night's,
    // and the bar says the search is empty.
    if (old.initialQuery != widget.initialQuery) {
      _field.text = widget.initialQuery;
      _adopt(widget.initialQuery);
    }
  }

  /// Takes the location's query as the one being answered.
  ///
  /// Unconditionally, including the empty case: the query, the scope, and
  /// the expanded groups all outlive this screen, so a bare `/search`
  /// after a previous search has to put every one of them back or the
  /// results, the filter, or the "Show all" belong to a search nobody can
  /// see. Posted rather than set inline because a provider cannot be
  /// written to during a build.
  void _adopt(String query) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(searchQueryProvider.notifier).submit(query);
      ref.read(searchScopeProvider.notifier).select(SearchScope.all);
      if (_expanded.isNotEmpty) setState(_expanded.clear);
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Puts the query that is being answered into the address bar.
  ///
  /// Driven by the settled query rather than by the keystroke, so what
  /// the URL says and what the screen shows are the same thing: a result
  /// set is only a link if it is in the bar without anyone pressing
  /// Enter for it.
  ///
  /// `replace`, not `go`. Search is one location whose query changes, so
  /// back should leave it rather than walk back through every prefix
  /// somebody typed — and on web `go` mints a browser history entry per
  /// call, which is exactly that walk.
  void _publish(String query) {
    if (!mounted) return;
    final location = WaxRoute.searchFor(query);
    if (GoRouterState.of(context).uri.toString() == location) return;
    context.replace(location);
  }

  void _onChanged(String value) {
    ref.read(searchQueryProvider.notifier).type(value);
  }

  void _onSubmitted(String value) {
    final trimmed = value.trim();
    ref.read(searchQueryProvider.notifier).submit(trimmed);
    ref.read(recentSearchesProvider.notifier).remember(trimmed);
  }

  void _runRecent(String query) {
    _field.text = query;
    ref.read(searchQueryProvider.notifier).submit(query);
    ref.read(recentSearchesProvider.notifier).remember(query);
  }

  void _open(SearchHit hit) {
    // Every hit is a place except a track, which is a thing to play. The
    // pid's own prefix says which, because the search contract mints hits
    // with the same type-prefixed ids the rest of the API uses.
    switch (hit.kind) {
      case 'artist':
        context.go(WaxRoute.musicBucket(MusicDimension.artists, hit.pid));
      case 'album':
        context.go(WaxRoute.musicBucket(MusicDimension.albums, hit.pid));
      case 'book':
        // Pushed, not gone to, and for the same reason the music
        // listings push one: a book is declared under home, so `go`
        // rebuilds that ancestry and discards the stack it was standing
        // in. An artist or an episode is a domain switch, which is what
        // `go` is for; a book from here is an excursion.
        context.push(WaxRoute.book(hit.pid));
      case 'episode':
        context.go(WaxRoute.episode(hit.pid));
      default:
        // A result row is one item with no list around it: the hits above
        // and below it are albums and shows, not a queue.
        ref.read(nowPlayingProvider.notifier).playPids(
          <String>[hit.pid],
          source: QueueSource(
            kind: QueueSourceKind.search,
            label: hit.title,
            pid: hit.pid,
          ),
        );
        context.push(WaxRoute.nowPlaying);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The one place the address bar is written: every route into a query
    // — typing, submitting, a recent search, arriving on a link — ends at
    // this provider, so following it is what keeps the two in step
    // without four call sites remembering to.
    ref.listen<String>(searchQueryProvider, (previous, next) {
      _publish(next);
      // "Show all" belongs to the group it was pressed on, in the answer
      // it was pressed in; carrying it into the next query expands a
      // group nobody asked to see all of.
      if (_expanded.isNotEmpty) setState(_expanded.clear);
    });
    final scope = ref.watch(searchScopeProvider);
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);

    return WaxScaffold(
      title: 'Search',
      largeTitle: false,
      onBack: () => context.go(WaxRoute.home),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: WaxSizeClass.of(
              context,
            ).gutter.copyWith(bottom: WaxSpace.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SearchField(
                  controller: _field,
                  focusNode: _focus,
                  autofocus: true,
                  hint: 'Artists, albums, shows, books',
                  onChanged: _onChanged,
                  onSubmitted: _onSubmitted,
                  semanticsId: SemanticsIds.searchField,
                  clearSemanticsId: SemanticsIds.searchClear,
                ),
                const SizedBox(height: WaxSpace.s12),
                FilterChipRow(
                  chips: <WaxFilterChip>[
                    for (final value in SearchScope.values)
                      WaxFilterChip(
                        name: value.name,
                        label: value.label,
                        semanticsId: SemanticsIds.searchFilter(value.name),
                      ),
                  ],
                  selected: scope.name,
                  onSelect: (name) => ref
                      .read(searchScopeProvider.notifier)
                      .select(SearchScope.byName(name)),
                ),
              ],
            ),
          ),
        ),
        ..._body(query: query, scope: scope, results: results),
      ],
    );
  }

  List<Widget> _body({
    required String query,
    required SearchScope scope,
    required AsyncValue<SearchResults?> results,
  }) {
    if (query.isEmpty) return _recents();
    return switch (results) {
      AsyncData(:final value) when value != null => _groups(value, scope),
      AsyncError(:final error) => <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorState(
            title: 'Could not search',
            message: error is WaxDeckApiException
                ? error.message
                : 'The server did not answer.',
            onRetry: () => ref.invalidate(searchResultsProvider),
          ),
        ),
      ],
      _ => const <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: SkeletonShapes(shape: SkeletonShape.list),
        ),
      ],
    };
  }

  List<Widget> _recents() {
    final recents = ref.watch(recentSearchesProvider);
    if (recents.isEmpty) {
      return const <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: 'Search your library',
            message: 'Try searching for an artist, show, or book.',
            glyph: WaxIcons.search,
          ),
        ),
      ];
    }
    return <Widget>[
      SliverPadding(
        padding: WaxSizeClass.of(context).gutter,
        sliver: SliverToBoxAdapter(
          child: SectionHeader(overline: 'Recent', title: 'Recent searches'),
        ),
      ),
      SliverList.builder(
        itemCount: recents.length,
        itemBuilder: (context, index) => Row(
          children: <Widget>[
            Expanded(
              child: MediaListRow(
                data: MediaTileData(
                  title: recents[index],
                  semanticsId: SemanticsIds.searchRecent(index),
                ),
                onTap: () => _runRecent(recents[index]),
              ),
            ),
            // Beside the row rather than as its overflow: a recent search
            // has exactly one thing to do to it, and a menu holding one
            // item is a menu nobody should have to open. Its own control,
            // so a screen reader finds two.
            WaxIconButton(
              glyph: WaxIcons.close,
              label: 'Forget ${recents[index]}',
              size: 16,
              semanticsId: SemanticsIds.searchRecentRemove(index),
              onPressed: () => ref
                  .read(recentSearchesProvider.notifier)
                  .forget(recents[index]),
            ),
            SizedBox(width: WaxSizeClass.of(context).gutter.right),
          ],
        ),
      ),
    ];
  }

  List<Widget> _groups(SearchResults results, SearchScope scope) {
    final slivers = <Widget>[];
    var found = 0;
    for (final kind in SearchHitKind.values) {
      if (!scope.covers(kind)) continue;
      final hits = kind.from(results);
      if (hits.isEmpty) continue;
      found += hits.length;
      final expanded = _expanded.contains(kind);
      final shown = expanded ? hits : hits.take(searchGroupPreview).toList();
      slivers.add(
        SliverPadding(
          padding: WaxSizeClass.of(context).gutter.copyWith(top: WaxSpace.s8),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(
              title: kind.label,
              actionLabel: hits.length > searchGroupPreview && !expanded
                  ? 'Show all'
                  : null,
              semanticsId: SemanticsIds.searchShowAll(kind.name),
              onAction: () => setState(() => _expanded.add(kind)),
            ),
          ),
        ),
      );
      slivers.add(
        SliverList.builder(
          itemCount: shown.length,
          itemBuilder: (context, index) => MediaListRow(
            data: MediaTileData(
              title: shown[index].title,
              subtitle: shown[index].subtitle,
              shape: kind == SearchHitKind.artists
                  ? ArtworkShape.circle
                  : ArtworkShape.square,
              domain: switch (kind) {
                SearchHitKind.episodes => WaxDomain.podcasts,
                SearchHitKind.books => WaxDomain.audiobooks,
                _ => WaxDomain.music,
              },
              semanticsId: SemanticsIds.searchHit(kind.name, index),
            ),
            onTap: () => _open(shown[index]),
          ),
        ),
      );
    }

    if (found == 0) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: 'Nothing for "${ref.read(searchQueryProvider)}"',
            message: 'Check the spelling or try fewer words.',
            glyph: WaxIcons.search,
          ),
        ),
      ];
    }
    if (results.truncated) {
      slivers.add(
        SliverPadding(
          padding: WaxSizeClass.of(
            context,
          ).gutter.copyWith(top: WaxSpace.s16, bottom: WaxSpace.s16),
          sliver: SliverToBoxAdapter(
            child: Semantics(
              identifier: SemanticsIds.searchTruncated,
              child: Text(
                'There are more matches than fit here. Refine your search to '
                'narrow them down.',
                style: WaxType.caption.copyWith(
                  color: WaxColors.of(context).textTertiary,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return slivers;
  }
}
