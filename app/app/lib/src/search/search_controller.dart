import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// Which kinds of result the filter chips narrow to.
enum SearchScope {
  all('all', 'All'),
  music('music', 'Music'),
  podcasts('podcasts', 'Podcasts'),
  books('books', 'Audiobooks');

  const SearchScope(this.name, this.label);

  final String name;
  final String label;

  /// The result groups this scope shows. Artists, albums, and tracks are
  /// all music; a scope that hid two of the three would be a filter on
  /// the shape of a hit rather than on what it is.
  bool covers(SearchHitKind kind) => switch (this) {
    SearchScope.all => true,
    SearchScope.music =>
      kind == SearchHitKind.artists ||
          kind == SearchHitKind.albums ||
          kind == SearchHitKind.tracks,
    SearchScope.podcasts => kind == SearchHitKind.episodes,
    SearchScope.books => kind == SearchHitKind.books,
  };

  static SearchScope byName(String name) =>
      SearchScope.values.firstWhere((s) => s.name == name);
}

/// One group of results, in the order the screen lists them.
enum SearchHitKind {
  artists('artists', 'Artists'),
  albums('albums', 'Albums'),
  tracks('tracks', 'Tracks'),
  books('books', 'Audiobooks'),
  episodes('episodes', 'Episodes');

  const SearchHitKind(this.name, this.label);

  final String name;
  final String label;

  List<SearchHit> from(SearchResults results) => switch (this) {
    SearchHitKind.artists => results.artists,
    SearchHitKind.albums => results.albums,
    SearchHitKind.tracks => results.tracks,
    SearchHitKind.books => results.books,
    SearchHitKind.episodes => results.episodes,
  };
}

/// How many hits a group shows before "Show all" expands it in place.
const searchGroupPreview = 5;

/// The typed query, debounced.
///
/// The field reports every keystroke and this holds the last one back
/// until the typing stops: a search over a large catalog is a real query,
/// and firing one per character spends the server's time answering
/// prefixes nobody asked about.
class SearchQuery extends Notifier<String> {
  static const debounce = Duration(milliseconds: 250);

  Timer? _timer;

  @override
  String build() {
    ref.onDispose(() => _timer?.cancel());
    return '';
  }

  /// Sets the query after [debounce] of quiet.
  void type(String value) {
    _timer?.cancel();
    final trimmed = value.trim();
    // Clearing is not a query: it takes effect at once, because waiting a
    // quarter second to empty a list reads as a stuck screen.
    if (trimmed.isEmpty) {
      state = '';
      return;
    }
    _timer = Timer(debounce, () => state = trimmed);
  }

  /// Sets the query now: a submit, a recent search, an arriving URL.
  void submit(String value) {
    _timer?.cancel();
    state = value.trim();
  }
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

/// Which filter chip is chosen.
class SearchScopeController extends Notifier<SearchScope> {
  @override
  SearchScope build() => SearchScope.all;

  void select(SearchScope scope) => state = scope;
}

final searchScopeProvider =
    NotifierProvider<SearchScopeController, SearchScope>(
      SearchScopeController.new,
    );

/// The results for the current query. An empty query answers null rather
/// than an empty result set: "nothing typed yet" and "nothing matched"
/// are different screens.
final searchResultsProvider = FutureProvider<SearchResults?>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return null;
  return ref.watch(repositoryProvider).search(query);
});

/// The last few queries, newest first.
///
/// In memory for this phase. The client-settings store that would
/// persist them across launches lands with the settings phase, and the
/// list is per-device either way.
class RecentSearches extends Notifier<List<String>> {
  static const limit = 10;

  @override
  List<String> build() => const <String>[];

  void remember(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    state = <String>[
      trimmed,
      for (final previous in state)
        if (previous.toLowerCase() != trimmed.toLowerCase()) previous,
    ].take(limit).toList();
  }

  void forget(String query) => state = <String>[
    for (final previous in state)
      if (previous != query) previous,
  ];
}

final recentSearchesProvider = NotifierProvider<RecentSearches, List<String>>(
  RecentSearches.new,
);
