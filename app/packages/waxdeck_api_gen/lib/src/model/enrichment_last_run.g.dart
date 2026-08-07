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
