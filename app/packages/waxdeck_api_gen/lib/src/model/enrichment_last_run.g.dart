// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_last_run.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentLastRun extends EnrichmentLastRun {
  @override
  final int albumsSearched;
  @override
  final int albumsMatched;
  @override
  final int artistArtEnriched;
  @override
  final int artistArtMatched;
  @override
  final int trackFieldsEnriched;
  @override
  final int trackFieldsMatched;
  @override
  final int bookFieldsEnriched;
  @override
  final int bookFieldsMatched;
  @override
  final int albumFieldsEnriched;
  @override
  final int albumFieldsMatched;
  @override
  final int tagsWritten;
  @override
  final int tagsFailed;
  @override
  final int tagsUnrepresented;
  @override
  final int tagsSkipped;
  @override
  final DateTime? finishedAt;

  factory _$EnrichmentLastRun([
    void Function(EnrichmentLastRunBuilder)? updates,
  ]) => (EnrichmentLastRunBuilder()..update(updates))._build();

  _$EnrichmentLastRun._({
    required this.albumsSearched,
    required this.albumsMatched,
    required this.artistArtEnriched,
    required this.artistArtMatched,
    required this.trackFieldsEnriched,
    required this.trackFieldsMatched,
    required this.bookFieldsEnriched,
    required this.bookFieldsMatched,
    required this.albumFieldsEnriched,
    required this.albumFieldsMatched,
    required this.tagsWritten,
    required this.tagsFailed,
    required this.tagsUnrepresented,
    required this.tagsSkipped,
    this.finishedAt,
  }) : super._();
  @override
  EnrichmentLastRun rebuild(void Function(EnrichmentLastRunBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EnrichmentLastRunBuilder toBuilder() =>
      EnrichmentLastRunBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentLastRun &&
        albumsSearched == other.albumsSearched &&
        albumsMatched == other.albumsMatched &&
        artistArtEnriched == other.artistArtEnriched &&
        artistArtMatched == other.artistArtMatched &&
        trackFieldsEnriched == other.trackFieldsEnriched &&
        trackFieldsMatched == other.trackFieldsMatched &&
        bookFieldsEnriched == other.bookFieldsEnriched &&
        bookFieldsMatched == other.bookFieldsMatched &&
        albumFieldsEnriched == other.albumFieldsEnriched &&
        albumFieldsMatched == other.albumFieldsMatched &&
        tagsWritten == other.tagsWritten &&
        tagsFailed == other.tagsFailed &&
        tagsUnrepresented == other.tagsUnrepresented &&
        tagsSkipped == other.tagsSkipped &&
        finishedAt == other.finishedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, albumsSearched.hashCode);
    _$hash = $jc(_$hash, albumsMatched.hashCode);
    _$hash = $jc(_$hash, artistArtEnriched.hashCode);
    _$hash = $jc(_$hash, artistArtMatched.hashCode);
    _$hash = $jc(_$hash, trackFieldsEnriched.hashCode);
    _$hash = $jc(_$hash, trackFieldsMatched.hashCode);
    _$hash = $jc(_$hash, bookFieldsEnriched.hashCode);
    _$hash = $jc(_$hash, bookFieldsMatched.hashCode);
    _$hash = $jc(_$hash, albumFieldsEnriched.hashCode);
    _$hash = $jc(_$hash, albumFieldsMatched.hashCode);
    _$hash = $jc(_$hash, tagsWritten.hashCode);
    _$hash = $jc(_$hash, tagsFailed.hashCode);
    _$hash = $jc(_$hash, tagsUnrepresented.hashCode);
    _$hash = $jc(_$hash, tagsSkipped.hashCode);
    _$hash = $jc(_$hash, finishedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichmentLastRun')
          ..add('albumsSearched', albumsSearched)
          ..add('albumsMatched', albumsMatched)
          ..add('artistArtEnriched', artistArtEnriched)
          ..add('artistArtMatched', artistArtMatched)
          ..add('trackFieldsEnriched', trackFieldsEnriched)
          ..add('trackFieldsMatched', trackFieldsMatched)
          ..add('bookFieldsEnriched', bookFieldsEnriched)
          ..add('bookFieldsMatched', bookFieldsMatched)
          ..add('albumFieldsEnriched', albumFieldsEnriched)
          ..add('albumFieldsMatched', albumFieldsMatched)
          ..add('tagsWritten', tagsWritten)
          ..add('tagsFailed', tagsFailed)
          ..add('tagsUnrepresented', tagsUnrepresented)
          ..add('tagsSkipped', tagsSkipped)
          ..add('finishedAt', finishedAt))
        .toString();
  }
}

class EnrichmentLastRunBuilder
    implements Builder<EnrichmentLastRun, EnrichmentLastRunBuilder> {
  _$EnrichmentLastRun? _$v;

  int? _albumsSearched;
  int? get albumsSearched => _$this._albumsSearched;
  set albumsSearched(int? albumsSearched) =>
      _$this._albumsSearched = albumsSearched;

  int? _albumsMatched;
  int? get albumsMatched => _$this._albumsMatched;
  set albumsMatched(int? albumsMatched) =>
      _$this._albumsMatched = albumsMatched;

  int? _artistArtEnriched;
  int? get artistArtEnriched => _$this._artistArtEnriched;
  set artistArtEnriched(int? artistArtEnriched) =>
      _$this._artistArtEnriched = artistArtEnriched;

  int? _artistArtMatched;
  int? get artistArtMatched => _$this._artistArtMatched;
  set artistArtMatched(int? artistArtMatched) =>
      _$this._artistArtMatched = artistArtMatched;

  int? _trackFieldsEnriched;
  int? get trackFieldsEnriched => _$this._trackFieldsEnriched;
  set trackFieldsEnriched(int? trackFieldsEnriched) =>
      _$this._trackFieldsEnriched = trackFieldsEnriched;

  int? _trackFieldsMatched;
  int? get trackFieldsMatched => _$this._trackFieldsMatched;
  set trackFieldsMatched(int? trackFieldsMatched) =>
      _$this._trackFieldsMatched = trackFieldsMatched;

  int? _bookFieldsEnriched;
  int? get bookFieldsEnriched => _$this._bookFieldsEnriched;
  set bookFieldsEnriched(int? bookFieldsEnriched) =>
      _$this._bookFieldsEnriched = bookFieldsEnriched;

  int? _bookFieldsMatched;
  int? get bookFieldsMatched => _$this._bookFieldsMatched;
  set bookFieldsMatched(int? bookFieldsMatched) =>
      _$this._bookFieldsMatched = bookFieldsMatched;

  int? _albumFieldsEnriched;
  int? get albumFieldsEnriched => _$this._albumFieldsEnriched;
  set albumFieldsEnriched(int? albumFieldsEnriched) =>
      _$this._albumFieldsEnriched = albumFieldsEnriched;

  int? _albumFieldsMatched;
  int? get albumFieldsMatched => _$this._albumFieldsMatched;
  set albumFieldsMatched(int? albumFieldsMatched) =>
      _$this._albumFieldsMatched = albumFieldsMatched;

  int? _tagsWritten;
  int? get tagsWritten => _$this._tagsWritten;
  set tagsWritten(int? tagsWritten) => _$this._tagsWritten = tagsWritten;

  int? _tagsFailed;
  int? get tagsFailed => _$this._tagsFailed;
  set tagsFailed(int? tagsFailed) => _$this._tagsFailed = tagsFailed;

  int? _tagsUnrepresented;
  int? get tagsUnrepresented => _$this._tagsUnrepresented;
  set tagsUnrepresented(int? tagsUnrepresented) =>
      _$this._tagsUnrepresented = tagsUnrepresented;

  int? _tagsSkipped;
  int? get tagsSkipped => _$this._tagsSkipped;
  set tagsSkipped(int? tagsSkipped) => _$this._tagsSkipped = tagsSkipped;

  DateTime? _finishedAt;
  DateTime? get finishedAt => _$this._finishedAt;
  set finishedAt(DateTime? finishedAt) => _$this._finishedAt = finishedAt;

  EnrichmentLastRunBuilder() {
    EnrichmentLastRun._defaults(this);
  }

  EnrichmentLastRunBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _albumsSearched = $v.albumsSearched;
      _albumsMatched = $v.albumsMatched;
      _artistArtEnriched = $v.artistArtEnriched;
      _artistArtMatched = $v.artistArtMatched;
      _trackFieldsEnriched = $v.trackFieldsEnriched;
      _trackFieldsMatched = $v.trackFieldsMatched;
      _bookFieldsEnriched = $v.bookFieldsEnriched;
      _bookFieldsMatched = $v.bookFieldsMatched;
      _albumFieldsEnriched = $v.albumFieldsEnriched;
      _albumFieldsMatched = $v.albumFieldsMatched;
      _tagsWritten = $v.tagsWritten;
      _tagsFailed = $v.tagsFailed;
      _tagsUnrepresented = $v.tagsUnrepresented;
      _tagsSkipped = $v.tagsSkipped;
      _finishedAt = $v.finishedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentLastRun other) {
    _$v = other as _$EnrichmentLastRun;
  }

  @override
  void update(void Function(EnrichmentLastRunBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentLastRun build() => _build();

  _$EnrichmentLastRun _build() {
    final _$result =
        _$v ??
        _$EnrichmentLastRun._(
          albumsSearched: BuiltValueNullFieldError.checkNotNull(
            albumsSearched,
            r'EnrichmentLastRun',
            'albumsSearched',
          ),
          albumsMatched: BuiltValueNullFieldError.checkNotNull(
            albumsMatched,
            r'EnrichmentLastRun',
            'albumsMatched',
          ),
          artistArtEnriched: BuiltValueNullFieldError.checkNotNull(
            artistArtEnriched,
            r'EnrichmentLastRun',
            'artistArtEnriched',
          ),
          artistArtMatched: BuiltValueNullFieldError.checkNotNull(
            artistArtMatched,
            r'EnrichmentLastRun',
            'artistArtMatched',
          ),
          trackFieldsEnriched: BuiltValueNullFieldError.checkNotNull(
            trackFieldsEnriched,
            r'EnrichmentLastRun',
            'trackFieldsEnriched',
          ),
          trackFieldsMatched: BuiltValueNullFieldError.checkNotNull(
            trackFieldsMatched,
            r'EnrichmentLastRun',
            'trackFieldsMatched',
          ),
          bookFieldsEnriched: BuiltValueNullFieldError.checkNotNull(
            bookFieldsEnriched,
            r'EnrichmentLastRun',
            'bookFieldsEnriched',
          ),
          bookFieldsMatched: BuiltValueNullFieldError.checkNotNull(
            bookFieldsMatched,
            r'EnrichmentLastRun',
            'bookFieldsMatched',
          ),
          albumFieldsEnriched: BuiltValueNullFieldError.checkNotNull(
            albumFieldsEnriched,
            r'EnrichmentLastRun',
            'albumFieldsEnriched',
          ),
          albumFieldsMatched: BuiltValueNullFieldError.checkNotNull(
            albumFieldsMatched,
            r'EnrichmentLastRun',
            'albumFieldsMatched',
          ),
          tagsWritten: BuiltValueNullFieldError.checkNotNull(
            tagsWritten,
            r'EnrichmentLastRun',
            'tagsWritten',
          ),
          tagsFailed: BuiltValueNullFieldError.checkNotNull(
            tagsFailed,
            r'EnrichmentLastRun',
            'tagsFailed',
          ),
          tagsUnrepresented: BuiltValueNullFieldError.checkNotNull(
            tagsUnrepresented,
            r'EnrichmentLastRun',
            'tagsUnrepresented',
          ),
          tagsSkipped: BuiltValueNullFieldError.checkNotNull(
            tagsSkipped,
            r'EnrichmentLastRun',
            'tagsSkipped',
          ),
          finishedAt: finishedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
