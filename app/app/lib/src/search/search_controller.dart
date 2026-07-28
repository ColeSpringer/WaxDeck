import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart' show ClientSettingKeys;

import '../providers.dart';
import '../settings/client_settings_providers.dart';

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
/// Per-device rather than per-account, and stored where those go
/// (ADR-0027): what someone typed on this machine is a shortcut back to
/// it, not a fact about their library. JSON is the encoding because the
/// value is a list and a query may hold anything a keyboard emits — a
/// separator would eventually appear inside one.
class RecentSearches extends Notifier<List<String>>
    with StoredSetting<List<String>> {
  static const limit = 10;

  @override
  String get settingKey => ClientSettingKeys.recentSearches;

  @override
  List<String> get defaultValue => const <String>[];

  /// The one rule about what this list may hold: newest first, no two
  /// casings of the same query, never longer than [limit]. Everything
  /// that builds a list goes through it, so a value that arrived from
  /// storage obeys it as surely as one just typed — an older build with
  /// a larger cap, or a hand-edited entry, cannot leave the list in a
  /// shape the rest of the class does not expect.
  static List<String> _capped(Iterable<String> queries) {
    final seen = <String>{};
    final kept = <String>[];
    for (final query in queries) {
      final trimmed = query.trim();
      if (trimmed.isEmpty) continue;
      if (!seen.add(trimmed.toLowerCase())) continue;
      kept.add(trimmed);
      if (kept.length == limit) break;
    }
    return kept;
  }

  /// Anything that is not a list of strings reads as nothing stored. The
  /// alternative is a search screen that throws at launch over a value
  /// nobody would miss.
  @override
  List<String>? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return _capped(<String>[
        for (final entry in decoded)
          if (entry is String) entry,
      ]);
    } on FormatException {
      return null;
    }
  }

  /// A search remembered before the stored list arrived does not throw
  /// that list away — it goes on the front of it. The base behavior
  /// would be right for a preference naming one thing and is a permanent
  /// data loss for one that accumulates: the write that followed the
  /// first search would have persisted a one-entry history over
  /// everything that was there.
  @override
  List<String> merge(List<String> mine, List<String> stored) =>
      _capped([...mine, ...stored]);

  @override
  String encode(List<String> value) => jsonEncode(value);

  @override
  List<String> build() => hydrate();

  void remember(String query) {
    if (query.trim().isEmpty) return;
    put(_capped([query, ...state]));
  }

  /// Matched the way [remember] deduplicates, because those two have to
  /// agree on what counts as the same query: the list can only ever hold
  /// one casing of a query, so forgetting another casing of it has to
  /// mean that one. Today every caller passes a string it read off the
  /// list, so this costs nothing; a search-history screen that forgets
  /// what was typed rather than what was drawn is where it would have.
  void forget(String query) {
    final target = query.trim().toLowerCase();
    put(<String>[
      for (final previous in state)
        if (previous.toLowerCase() != target) previous,
    ]);
  }
}

final recentSearchesProvider = NotifierProvider<RecentSearches, List<String>>(
  RecentSearches.new,
);

/// What search leaves behind when a session ends: nothing.
///
/// The store these live in is per-device and a sign-out deliberately
/// leaves most of it standing — a collapsed sidebar describes the
/// machine, not the account. This key is the exception, and the
/// distinction is worth being exact about: recent searches are strings
/// the departing listener typed, and they name artists, albums, and
/// books in *their* library. On web they sit in origin-scoped
/// `localStorage`, which is to say in a place the next account to use
/// this browser reads back. That makes them the departing account's
/// content, like the queue and the cached artwork, and they go the same
/// way. See ADR-0027.
///
/// Never throws. A history that will not clear is not a reason to leave
/// the session standing, and a session left standing is a dead
/// credential the UI keeps using.
Future<void> forgetSearchesOnSignOut(Ref ref) =>
    ref.read(recentSearchesProvider.notifier).clearStored();
