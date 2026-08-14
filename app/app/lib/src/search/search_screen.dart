import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../home/pin_action.dart';
import '../l10n/l10n.dart';
import '../podcasts/podcasts_controller.dart';
import '../radio/add_station.dart';
import '../radio/radio_screen.dart';
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
    if (ref.read(searchScopeProvider).source.asksLibrary) {
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
      // The field follows the query whoever set it, which is what keeps
      // this screen's field and the shell header's from drifting apart.
      // Only one of the two is on screen at a time, so the one that was
      // hidden while the other was typed in has to catch up before it is
      // shown - and `didUpdateWidget` cannot do it: the location this
      // screen writes on every keystroke returns early there on purpose,
      // so the filter chip is not reset per character. The guard is the
      // same one the header uses: assigning text the field already holds
      // would move the caret to the end mid-word.
      if (_field.text.trim() != next) _field.text = next;
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
    final l10n = context.l10n;

    return WaxScaffold(
      title: l10n.searchTitle,
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
                    hint: l10n.searchFieldHint,
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
                        label: value.labelOf(l10n),
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
    if (scope.source == SearchSource.directory) return _directory(query);
    if (query.isEmpty) return _recents();

    // Built here rather than inside the library results, and that is
    // what makes the two halves independent. Reading it only in the
    // AsyncData branch meant the directory was not even *watched* until
    // the library search had come back, so two calls that could have
    // gone out together went out one after the other - and a library
    // search that failed took the whole directory half down with it,
    // even though the two ask different servers different questions.
    final directory = scope.source.asksDirectory
        ? _podcastDirectory(query)
        : const <Widget>[];
    // Local stations cost no round trip at all: the list is already
    // loaded. They belong under any chip that shows library results.
    final stations = _localStations();

    return switch (results) {
      AsyncData(:final value) when value != null => _groups(
        value,
        scope,
        stations,
        directory,
      ),
      // Typed rather than the `:final error` shorthand: `hasError` is
      // `error != null`, so binding it as an Object is exact and the
      // sentence below needs no null check.
      AsyncValue(hasError: true, error: final Object error) => <Widget>[
        ...stations,
        SliverToBoxAdapter(
          child: ErrorState(
            title: context.l10n.searchFailedTitle,
            message: context.explain(error),
            onRetry: () => ref.invalidate(searchResultsProvider),
          ),
        ),
        ...directory,
      ],
      _ => <Widget>[
        ...stations,
        // Not SliverFillRemaining while there is a directory half to
        // draw: filling the viewport would push it past the fold, which
        // for a result set that has already arrived is the same as
        // hiding it.
        if (stations.isEmpty && directory.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: SkeletonShapes(shape: SkeletonShape.list),
          )
        else
          const SliverToBoxAdapter(
            child: SkeletonShapes(shape: SkeletonShape.list, count: 3),
          ),
        ...directory,
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
    final l10n = context.l10n;
    if (query.length < 2) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: l10n.searchDirectoryPromptTitle,
            message: l10n.searchDirectoryPromptMessage,
            glyph: WaxIcons.radio,
          ),
        ),
      ];
    }
    // Stations already here come first, and they play rather than being
    // offered for adding: someone searching for a station they have has
    // asked to listen to it, and the directory's copy of the same
    // station is the wrong row to hand them.
    final local = _localStations();
    final entries = ref.watch(radioDirectoryResultsProvider);
    return switch (entries) {
      AsyncData(:final value) when value == null || value.isEmpty => <Widget>[
        ...local,
        if (local.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.searchNoStationsTitle(query),
              message: l10n.searchNoStationsMessage,
              glyph: WaxIcons.radio,
            ),
          ),
      ],
      AsyncData(:final value) => <Widget>[
        ...local,
        if (local.isNotEmpty)
          SliverPadding(
            padding: WaxSizeClass.of(context).gutter.copyWith(top: WaxSpace.s8),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(
                overline: l10n.searchDirectoryOverline,
                title: l10n.searchStationsToAdd,
              ),
            ),
          ),
        SliverList.builder(
          itemCount: value!.length,
          itemBuilder: (context, index) => WaxOptionRow(
            title: value[index].name,
            subtitle: describeDirectoryEntry(context.l10n, value[index]),
            glyph: WaxIcons.radio,
            semanticsId: SemanticsIds.searchHit('radio', index),
            trailing: WaxButton(
              label: l10n.searchAddStation,
              kind: WaxButtonKind.tonal,
              icon: WaxIcons.add,
              semanticsId: SemanticsIds.radioSearchAdd(index),
              onPressed: () => unawaited(_addStation(value[index])),
            ),
          ),
        ),
      ],
      // The stations already here are not the directory's to lose. With
      // some listed, the failure is a line under them; with none, it is
      // the whole answer and gets the whole screen. A SliverFillRemaining
      // under a filled list would be pushed past the fold, which is the
      // same as not reporting it.
      //
      // Matched on hasError rather than on AsyncError, because a retry in
      // flight is an AsyncLoading still carrying the failure it is
      // retrying. Matching the settled state alone would replace the
      // reported problem with a skeleton for as long as the directory
      // keeps failing, which is exactly when it must not.
      AsyncValue(hasError: true) when local.isNotEmpty => <Widget>[
        ...local,
        SliverPadding(
          padding: WaxSizeClass.of(context).gutter.copyWith(top: WaxSpace.s16),
          sliver: SliverToBoxAdapter(
            child: WaxBanner(
              message: l10n.searchDirectoryDegraded,
              tone: WaxBannerTone.caution,
              actionLabel: l10n.commonRetry,
              onAction: () => ref.invalidate(radioDirectoryResultsProvider),
            ),
          ),
        ),
      ],
      AsyncValue(hasError: true, error: final Object error) => <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorState(
            title: l10n.searchDirectoryErrorTitle,
            message: context.explain(error),
            // The way out the directory-unavailable mapping implies:
            // adding a station by URL works with no directory at all.
            detail: l10n.searchDirectoryErrorDetail,
            onRetry: () => ref.invalidate(radioDirectoryResultsProvider),
          ),
        ),
      ],
      _ => <Widget>[
        ...local,
        const SliverFillRemaining(
          hasScrollBody: false,
          child: SkeletonShapes(shape: SkeletonShape.list),
        ),
      ],
    };
  }

  /// Stations this library already holds, matched by name.
  ///
  /// The bug this closes is that they appeared nowhere in search at all:
  /// stations are not in the FTS index, so a station somebody added five
  /// minutes ago was unfindable by the surface built for finding things.
  List<Widget> _localStations() {
    final stations = ref.watch(localRadioMatchesProvider);
    if (stations.isEmpty) return const <Widget>[];
    return <Widget>[
      SliverPadding(
        padding: WaxSizeClass.of(context).gutter.copyWith(top: WaxSpace.s8),
        sliver: SliverToBoxAdapter(
          child: SectionHeader(
            overline: context.l10n.searchLibraryOverline,
            title: context.l10n.searchYourStations,
          ),
        ),
      ),
      SliverList.builder(
        itemCount: stations.length,
        itemBuilder: (context, index) => WaxOptionRow(
          title: stations[index].name,
          subtitle: stations[index].homepageUrl,
          glyph: WaxIcons.radio,
          semanticsId: SemanticsIds.searchHit('station', index),
          // Playing, not adding: it is already here.
          onTap: () => unawaited(tuneStation(context, ref, stations[index])),
        ),
      ),
    ];
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
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: context.l10n.searchEmptyTitle,
            message: context.l10n.searchEmptyMessage,
            glyph: WaxIcons.search,
          ),
        ),
      ];
    }
    return <Widget>[
      SliverPadding(
        padding: WaxSizeClass.of(context).gutter,
        sliver: SliverToBoxAdapter(
          child: SectionHeader(
            overline: context.l10n.searchRecentOverline,
            title: context.l10n.searchRecentTitle,
          ),
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
              label: context.l10n.searchForget(recents[index]),
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

  List<Widget> _groups(
    SearchResults results,
    SearchScope scope,
    List<Widget> stations,
    List<Widget> directory,
  ) {
    final slivers = <Widget>[...stations];
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
              title: kind.labelOf(context.l10n),
              actionLabel: hits.length > searchGroupPreview && !expanded
                  ? context.l10n.searchShowAll
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
          itemBuilder: (context, index) {
            final hit = shown[index];
            // A hit that names a pinnable thing can be pinned from
            // here; a track or an episode cannot, and the hit carries
            // no handle to its container.
            final pinnable = switch (hit.kind) {
              'artist' || 'album' || 'book' => true,
              _ => false,
            };
            return MediaListRow(
              data: MediaTileData(
                title: hit.title,
                subtitle: hit.subtitle,
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
              onTap: () => _open(hit),
              onMore: pinnable
                  ? () => showPinSheet(
                      context,
                      ref,
                      targets: <PinTarget>[
                        (pid: hit.pid, what: hit.kind, name: hit.title),
                      ],
                    )
                  : null,
              moreSemanticsId: SemanticsIds.searchHitMore(kind.name, index),
            );
          },
        ),
      );
    }

    // A query that matched nothing in the library can still have matched
    // a station already here or a show in the directory, and "nothing for
    // that" over a list of results is the wrong screen.
    if (found == 0 && directory.isEmpty && stations.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: context.l10n.searchNothingTitle(
              ref.read(searchQueryProvider),
            ),
            message: context.l10n.searchNothingMessage,
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
                context.l10n.searchTruncated,
                style: WaxType.caption.copyWith(
                  color: WaxColors.of(context).textTertiary,
                ),
              ),
            ),
          ),
        ),
      );
    }
    slivers.addAll(directory);
    return slivers;
  }

  /// The podcast directory, under the library's own episodes.
  ///
  /// Unlike the station directory this is never the whole answer, which
  /// decides every difference from [_directory]: it draws no full-screen
  /// empty state (the library above it is the answer), and a directory
  /// that will not answer is a line beside the results rather than an
  /// error page over them. Returning an empty list means "nothing to add
  /// here", which is what lets the caller fall through to its own empty
  /// state when the library found nothing either.
  List<Widget> _podcastDirectory(String query) {
    if (query.length < 2) return const <Widget>[];
    final entries = ref.watch(podcastDirectoryResultsProvider);
    final header = SliverPadding(
      padding: WaxSizeClass.of(context).gutter.copyWith(top: WaxSpace.s8),
      sliver: SliverToBoxAdapter(
        child: SectionHeader(
          overline: context.l10n.searchDirectoryOverline,
          title: context.l10n.searchShowsToSubscribe,
        ),
      ),
    );
    return switch (entries) {
      AsyncData(:final value) when value == null || value.isEmpty =>
        const <Widget>[],
      AsyncData(:final value) => <Widget>[
        header,
        SliverList.builder(
          itemCount: value!.length,
          itemBuilder: (context, index) => WaxOptionRow(
            title: value[index].name,
            subtitle: describePodcastDirectoryEntry(context.l10n, value[index]),
            glyph: WaxIcons.podcasts,
            semanticsId: SemanticsIds.searchHit('podcastDirectory', index),
            trailing: WaxButton(
              label: context.l10n.searchSubscribe,
              kind: WaxButtonKind.tonal,
              icon: WaxIcons.add,
              semanticsId: SemanticsIds.podcastSearchSubscribe(index),
              onPressed: () => unawaited(_subscribeShow(value[index])),
            ),
          ),
        ),
      ],
      // hasError rather than AsyncError: a retry in flight is an
      // AsyncLoading still carrying the failure it is retrying, and a
      // skeleton in place of the reported problem is the wrong answer
      // for as long as the directory keeps failing.
      AsyncValue(hasError: true) => <Widget>[
        SliverPadding(
          padding: WaxSizeClass.of(context).gutter.copyWith(top: WaxSpace.s16),
          sliver: SliverToBoxAdapter(
            child: WaxBanner(
              message: context.l10n.searchPodcastDirectoryDegraded,
              tone: WaxBannerTone.caution,
              actionLabel: context.l10n.commonRetry,
              onAction: () => ref.invalidate(podcastDirectoryResultsProvider),
            ),
          ),
        ),
      ],
      _ => <Widget>[
        header,
        const SliverToBoxAdapter(
          child: SkeletonShapes(shape: SkeletonShape.list, count: 2),
        ),
      ],
    };
  }

  /// Subscribes to a directory match, reporting the outcome where there
  /// is no modal to put it in.
  Future<void> _subscribeShow(PodcastDirectoryEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    String message;
    try {
      // A directory match is always an RSS feed, so no source kind is
      // asked for or sent: the whole reason the endpoint returns
      // `feedUrl` is that the answer is already known. Through the
      // controller rather than the repository, so the hub's grid holds
      // the new show without being told about it separately.
      await ref
          .read(subscriptionsProvider.notifier)
          .subscribe(url: entry.feedUrl);
      message = l10n.searchSubscribed(entry.name);
    } on WaxDeckApiException catch (e) {
      // The feed URL came off the directory rather than out of a field,
      // so nothing anybody typed is what was refused: the table's own
      // sentence is the right one.
      message = explainError(l10n, e);
    }
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
