import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../radio/add_station.dart';
import '../shell/adaptive_shell.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'search_controller.dart';
import 'search_open.dart';

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
    if (old.initialQuery == widget.initialQuery) return;
    // The location moved because *this screen* put the settled query in
    // the address bar, which happens on every keystroke: there is nothing
    // to adopt from a location this screen wrote, and treating it as an
    // arrival resets the filter chip on every character typed. Picking
    // Podcasts and typing put the chips back to All; picking Radio did it
    // too, and there it also fired a library search the screen had no
    // group to show.
    if (widget.initialQuery == ref.read(searchQueryProvider)) return;
    // Arriving at `/search` while already on `/search?q=night` is one
    // click - the sidebar launcher is on screen the whole time, and so
    // is every rebuilt screen's search control. go_router keys a page by
    // its path and its path parameters, and a query is neither, so the
    // same State is reused and `initState` never runs again. Without
    // this the field still reads "night", the results are still night's,
    // and the bar says the search is empty.
    _field.text = widget.initialQuery;
    _adopt(widget.initialQuery);
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
  /// somebody typed - and on web `go` mints a browser history entry per
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
    // Library queries only. Recents are offered under the library chips
    // and not the Radio one, so an entry stored here would be a shortcut
    // that runs a library search for a station name.
    if (!ref.read(searchScopeProvider).isDirectory) {
      ref.read(recentSearchesProvider.notifier).remember(trimmed);
    }
  }

  void _runRecent(String query) {
    _field.text = query;
    ref.read(searchQueryProvider.notifier).submit(query);
    ref.read(recentSearchesProvider.notifier).remember(query);
  }

  /// What a row opens, which the command palette's own hits share
  /// (`openSearchHit`): two surfaces answering one query must not
  /// disagree about where a result goes.
  void _open(SearchHit hit) => openSearchHit(context, ref, hit);

  @override
  Widget build(BuildContext context) {
    // The one place the address bar is written: every route into a query
    // typing, submitting, a recent search, arriving on a link - ends at
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
    // The shell's sidebar header is a live field wherever it is drawn, so
    // this screen draws one only where it is not: two fields holding one
    // query is the synchronisation problem the launcher used to avoid by
    // being dead. A collapsed sidebar drops the header, so the width
    // alone is not the question.
    final ownField =
        !WaxSizeClass.of(context).hasSidebar ||
        ref.watch(sidebarCollapsedProvider);

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
                if (ownField) ...<Widget>[
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
                ],
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
    // The directory scope answers first, including with nothing typed: the
    // recent searches are queries put to the *library*, and offering them
    // under a chip that searches the station directory would put a shortcut
    // to the wrong surface behind them. What an empty Radio chip owes is
    // "here is what typing will do".
    if (scope.isDirectory) return _directory(query);
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

  /// The station directory, under the Radio chip.
  ///
  /// A different question of a different surface: these are stations this
  /// server does not have, so every row's action is "add", not "play". The
  /// add flow is the radio hub's own - one directory, one way of adding
  /// from it, so a station added here is a station the dial will draw with
  /// its logo through the proxy.
  List<Widget> _directory(String query) {
    if (query.length < 2) {
      return const <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: 'Search the station directory',
            message:
                'Type a station name to look it up in the public directory, '
                'then add it to this server.',
            glyph: WaxIcons.radio,
          ),
        ),
      ];
    }
    final entries = ref.watch(radioDirectoryResultsProvider);
    return switch (entries) {
      AsyncData(:final value) when value == null || value.isEmpty => <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: 'No stations for "$query"',
            message: 'The directory lists nothing under that name.',
            glyph: WaxIcons.radio,
          ),
        ),
      ],
      AsyncData(:final value) => <Widget>[
        SliverList.builder(
          itemCount: value!.length,
          itemBuilder: (context, index) => WaxOptionRow(
            title: value[index].name,
            subtitle: describeDirectoryEntry(value[index]),
            glyph: WaxIcons.radio,
            semanticsId: SemanticsIds.searchHit('radio', index),
            trailing: WaxButton(
              label: 'Add station',
              kind: WaxButtonKind.tonal,
              icon: WaxIcons.add,
              semanticsId: SemanticsIds.radioSearchAdd(index),
              onPressed: () => unawaited(_addStation(value[index])),
            ),
          ),
        ),
      ],
      AsyncError(:final error) => <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorState(
            title: 'Could not reach the directory',
            message: error is WaxDeckApiException
                ? error.message
                : 'The station directory did not answer.',
            // The way out the directory-unavailable mapping implies:
            // adding a station by URL works with no directory at all.
            detail: 'Adding a station by its stream URL still works.',
            onRetry: () => ref.invalidate(radioDirectoryResultsProvider),
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

  /// Adds a directory match, reporting a refusal where there is no modal to
  /// hide a snackbar behind.
  Future<void> _addStation(RadioDirectoryEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final refusal = await addDirectoryStation(context, ref, entry);
    if (refusal == null || !mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(refusal)));
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
