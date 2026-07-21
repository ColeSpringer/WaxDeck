// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_coverage.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentCoverage extends EnrichmentCoverage {
  @override
  final CoverageCount artists;
  @override
  final CoverageCount releaseGroups;
  @override
  final CoverageCount books;
  @override
  final CoverageCount lyrics;

  factory _$EnrichmentCoverage([
    void Function(EnrichmentCoverageBuilder)? updates,
  ]) => (EnrichmentCoverageBuilder()..update(updates))._build();

  _$EnrichmentCoverage._({
    required this.artists,
    required this.releaseGroups,
    required this.books,
    required this.lyrics,
  }) : super._();
  @override
  EnrichmentCoverage rebuild(
    void Function(EnrichmentCoverageBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EnrichmentCoverageBuilder toBuilder() =>
      EnrichmentCoverageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentCoverage &&
        artists == other.artists &&
        releaseGroups == other.releaseGroups &&
        books == other.books &&
        lyrics == other.lyrics;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, artists.hashCode);
    _$hash = $jc(_$hash, releaseGroups.hashCode);
    _$hash = $jc(_$hash, books.hashCode);
    _$hash = $jc(_$hash, lyrics.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichmentCoverage')
          ..add('artists', artists)
          ..add('releaseGroups', releaseGroups)
          ..add('books', books)
          ..add('lyrics', lyrics))
        .toString();
  }
}

class EnrichmentCoverageBuilder
    implements Builder<EnrichmentCoverage, EnrichmentCoverageBuilder> {
  _$EnrichmentCoverage? _$v;

  CoverageCountBuilder? _artists;
  CoverageCountBuilder get artists =>
      _$this._artists ??= CoverageCountBuilder();
  set artists(CoverageCountBuilder? artists) => _$this._artists = artists;

  CoverageCountBuilder? _releaseGroups;
  CoverageCountBuilder get releaseGroups =>
      _$this._releaseGroups ??= CoverageCountBuilder();
  set releaseGroups(CoverageCountBuilder? releaseGroups) =>
      _$this._releaseGroups = releaseGroups;

  CoverageCountBuilder? _books;
  CoverageCountBuilder get books => _$this._books ??= CoverageCountBuilder();
  set books(CoverageCountBuilder? books) => _$this._books = books;

  CoverageCountBuilder? _lyrics;
  CoverageCountBuilder get lyrics => _$this._lyrics ??= CoverageCountBuilder();
  set lyrics(CoverageCountBuilder? lyrics) => _$this._lyrics = lyrics;

  EnrichmentCoverageBuilder() {
    EnrichmentCoverage._defaults(this);
  }

  EnrichmentCoverageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _artists = $v.artists.toBuilder();
      _releaseGroups = $v.releaseGroups.toBuilder();
      _books = $v.books.toBuilder();
      _lyrics = $v.lyrics.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentCoverage other) {
    _$v = other as _$EnrichmentCoverage;
  }

  @override
  void update(void Function(EnrichmentCoverageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentCoverage build() => _build();

  _$EnrichmentCoverage _build() {
    _$EnrichmentCoverage _$result;
    try {
      _$result =
          _$v ??
          _$EnrichmentCoverage._(
            artists: artists.build(),
            releaseGroups: releaseGroups.build(),
            books: books.build(),
            lyrics: lyrics.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'artists';
        artists.build();
        _$failedField = 'releaseGroups';
        releaseGroups.build();
        _$failedField = 'books';
        books.build();
        _$failedField = 'lyrics';
        lyrics.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EnrichmentCoverage',
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
