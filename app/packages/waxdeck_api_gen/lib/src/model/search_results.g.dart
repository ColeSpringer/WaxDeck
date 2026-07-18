// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_results.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SearchResults extends SearchResults {
  @override
  final String query;
  @override
  final BuiltList<SearchHit> artists;
  @override
  final BuiltList<SearchHit> albums;
  @override
  final BuiltList<SearchHit> tracks;
  @override
  final BuiltList<SearchHit> books;
  @override
  final BuiltList<SearchHit> episodes;
  @override
  final bool? truncated;

  factory _$SearchResults([void Function(SearchResultsBuilder)? updates]) =>
      (SearchResultsBuilder()..update(updates))._build();

  _$SearchResults._({
    required this.query,
    required this.artists,
    required this.albums,
    required this.tracks,
    required this.books,
    required this.episodes,
    this.truncated,
  }) : super._();
  @override
  SearchResults rebuild(void Function(SearchResultsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SearchResultsBuilder toBuilder() => SearchResultsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SearchResults &&
        query == other.query &&
        artists == other.artists &&
        albums == other.albums &&
        tracks == other.tracks &&
        books == other.books &&
        episodes == other.episodes &&
        truncated == other.truncated;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, query.hashCode);
    _$hash = $jc(_$hash, artists.hashCode);
    _$hash = $jc(_$hash, albums.hashCode);
    _$hash = $jc(_$hash, tracks.hashCode);
    _$hash = $jc(_$hash, books.hashCode);
    _$hash = $jc(_$hash, episodes.hashCode);
    _$hash = $jc(_$hash, truncated.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SearchResults')
          ..add('query', query)
          ..add('artists', artists)
          ..add('albums', albums)
          ..add('tracks', tracks)
          ..add('books', books)
          ..add('episodes', episodes)
          ..add('truncated', truncated))
        .toString();
  }
}

class SearchResultsBuilder
    implements Builder<SearchResults, SearchResultsBuilder> {
  _$SearchResults? _$v;

  String? _query;
  String? get query => _$this._query;
  set query(String? query) => _$this._query = query;

  ListBuilder<SearchHit>? _artists;
  ListBuilder<SearchHit> get artists =>
      _$this._artists ??= ListBuilder<SearchHit>();
  set artists(ListBuilder<SearchHit>? artists) => _$this._artists = artists;

  ListBuilder<SearchHit>? _albums;
  ListBuilder<SearchHit> get albums =>
      _$this._albums ??= ListBuilder<SearchHit>();
  set albums(ListBuilder<SearchHit>? albums) => _$this._albums = albums;

  ListBuilder<SearchHit>? _tracks;
  ListBuilder<SearchHit> get tracks =>
      _$this._tracks ??= ListBuilder<SearchHit>();
  set tracks(ListBuilder<SearchHit>? tracks) => _$this._tracks = tracks;

  ListBuilder<SearchHit>? _books;
  ListBuilder<SearchHit> get books =>
      _$this._books ??= ListBuilder<SearchHit>();
  set books(ListBuilder<SearchHit>? books) => _$this._books = books;

  ListBuilder<SearchHit>? _episodes;
  ListBuilder<SearchHit> get episodes =>
      _$this._episodes ??= ListBuilder<SearchHit>();
  set episodes(ListBuilder<SearchHit>? episodes) => _$this._episodes = episodes;

  bool? _truncated;
  bool? get truncated => _$this._truncated;
  set truncated(bool? truncated) => _$this._truncated = truncated;

  SearchResultsBuilder() {
    SearchResults._defaults(this);
  }

  SearchResultsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _query = $v.query;
      _artists = $v.artists.toBuilder();
      _albums = $v.albums.toBuilder();
      _tracks = $v.tracks.toBuilder();
      _books = $v.books.toBuilder();
      _episodes = $v.episodes.toBuilder();
      _truncated = $v.truncated;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SearchResults other) {
    _$v = other as _$SearchResults;
  }

  @override
  void update(void Function(SearchResultsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SearchResults build() => _build();

  _$SearchResults _build() {
    _$SearchResults _$result;
    try {
      _$result =
          _$v ??
          _$SearchResults._(
            query: BuiltValueNullFieldError.checkNotNull(
              query,
              r'SearchResults',
              'query',
            ),
            artists: artists.build(),
            albums: albums.build(),
            tracks: tracks.build(),
            books: books.build(),
            episodes: episodes.build(),
            truncated: truncated,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'artists';
        artists.build();
        _$failedField = 'albums';
        albums.build();
        _$failedField = 'tracks';
        tracks.build();
        _$failedField = 'books';
        books.build();
        _$failedField = 'episodes';
        episodes.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SearchResults',
          _$failedField,
          e.toString(),
        );
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
