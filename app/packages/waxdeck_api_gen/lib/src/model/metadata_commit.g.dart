// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata_commit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MetadataCommit extends MetadataCommit {
  @override
  final BuiltMap<String, String>? fields;
  @override
  final BuiltList<CommitCredits>? credits;
  @override
  final CommitLyrics? lyrics;
  @override
  final bool? clearLyrics;
  @override
  final BuiltList<ChapterMark>? chapters;
  @override
  final BuiltMap<String, BuiltList<String>>? tagSets;
  @override
  final BuiltList<String>? tagRemoves;
  @override
  final bool? unofficial;
  @override
  final bool? writeBack;
  @override
  final bool? lock;
  @override
  final bool? force;

  factory _$MetadataCommit([void Function(MetadataCommitBuilder)? updates]) =>
      (MetadataCommitBuilder()..update(updates))._build();

  _$MetadataCommit._({
    this.fields,
    this.credits,
    this.lyrics,
    this.clearLyrics,
    this.chapters,
    this.tagSets,
    this.tagRemoves,
    this.unofficial,
    this.writeBack,
    this.lock,
    this.force,
  }) : super._();
  @override
  MetadataCommit rebuild(void Function(MetadataCommitBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MetadataCommitBuilder toBuilder() => MetadataCommitBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MetadataCommit &&
        fields == other.fields &&
        credits == other.credits &&
        lyrics == other.lyrics &&
        clearLyrics == other.clearLyrics &&
        chapters == other.chapters &&
        tagSets == other.tagSets &&
        tagRemoves == other.tagRemoves &&
        unofficial == other.unofficial &&
        writeBack == other.writeBack &&
        lock == other.lock &&
        force == other.force;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, fields.hashCode);
    _$hash = $jc(_$hash, credits.hashCode);
    _$hash = $jc(_$hash, lyrics.hashCode);
    _$hash = $jc(_$hash, clearLyrics.hashCode);
    _$hash = $jc(_$hash, chapters.hashCode);
    _$hash = $jc(_$hash, tagSets.hashCode);
    _$hash = $jc(_$hash, tagRemoves.hashCode);
    _$hash = $jc(_$hash, unofficial.hashCode);
    _$hash = $jc(_$hash, writeBack.hashCode);
    _$hash = $jc(_$hash, lock.hashCode);
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MetadataCommit')
          ..add('fields', fields)
          ..add('credits', credits)
          ..add('lyrics', lyrics)
          ..add('clearLyrics', clearLyrics)
          ..add('chapters', chapters)
          ..add('tagSets', tagSets)
          ..add('tagRemoves', tagRemoves)
          ..add('unofficial', unofficial)
          ..add('writeBack', writeBack)
          ..add('lock', lock)
          ..add('force', force))
        .toString();
  }
}

class MetadataCommitBuilder
    implements Builder<MetadataCommit, MetadataCommitBuilder> {
  _$MetadataCommit? _$v;

  MapBuilder<String, String>? _fields;
  MapBuilder<String, String> get fields =>
      _$this._fields ??= MapBuilder<String, String>();
  set fields(MapBuilder<String, String>? fields) => _$this._fields = fields;

  ListBuilder<CommitCredits>? _credits;
  ListBuilder<CommitCredits> get credits =>
      _$this._credits ??= ListBuilder<CommitCredits>();
  set credits(ListBuilder<CommitCredits>? credits) => _$this._credits = credits;

  CommitLyricsBuilder? _lyrics;
  CommitLyricsBuilder get lyrics => _$this._lyrics ??= CommitLyricsBuilder();
  set lyrics(CommitLyricsBuilder? lyrics) => _$this._lyrics = lyrics;

  bool? _clearLyrics;
  bool? get clearLyrics => _$this._clearLyrics;
  set clearLyrics(bool? clearLyrics) => _$this._clearLyrics = clearLyrics;

  ListBuilder<ChapterMark>? _chapters;
  ListBuilder<ChapterMark> get chapters =>
      _$this._chapters ??= ListBuilder<ChapterMark>();
  set chapters(ListBuilder<ChapterMark>? chapters) =>
      _$this._chapters = chapters;

  MapBuilder<String, BuiltList<String>>? _tagSets;
  MapBuilder<String, BuiltList<String>> get tagSets =>
      _$this._tagSets ??= MapBuilder<String, BuiltList<String>>();
  set tagSets(MapBuilder<String, BuiltList<String>>? tagSets) =>
      _$this._tagSets = tagSets;

  ListBuilder<String>? _tagRemoves;
  ListBuilder<String> get tagRemoves =>
      _$this._tagRemoves ??= ListBuilder<String>();
  set tagRemoves(ListBuilder<String>? tagRemoves) =>
      _$this._tagRemoves = tagRemoves;

  bool? _unofficial;
  bool? get unofficial => _$this._unofficial;
  set unofficial(bool? unofficial) => _$this._unofficial = unofficial;

  bool? _writeBack;
  bool? get writeBack => _$this._writeBack;
  set writeBack(bool? writeBack) => _$this._writeBack = writeBack;

  bool? _lock;
  bool? get lock => _$this._lock;
  set lock(bool? lock) => _$this._lock = lock;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  MetadataCommitBuilder() {
    MetadataCommit._defaults(this);
  }

  MetadataCommitBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _fields = $v.fields?.toBuilder();
      _credits = $v.credits?.toBuilder();
      _lyrics = $v.lyrics?.toBuilder();
      _clearLyrics = $v.clearLyrics;
      _chapters = $v.chapters?.toBuilder();
      _tagSets = $v.tagSets?.toBuilder();
      _tagRemoves = $v.tagRemoves?.toBuilder();
      _unofficial = $v.unofficial;
      _writeBack = $v.writeBack;
      _lock = $v.lock;
      _force = $v.force;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MetadataCommit other) {
    _$v = other as _$MetadataCommit;
  }

  @override
  void update(void Function(MetadataCommitBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MetadataCommit build() => _build();

  _$MetadataCommit _build() {
    _$MetadataCommit _$result;
    try {
      _$result =
          _$v ??
          _$MetadataCommit._(
            fields: _fields?.build(),
            credits: _credits?.build(),
            lyrics: _lyrics?.build(),
            clearLyrics: clearLyrics,
            chapters: _chapters?.build(),
            tagSets: _tagSets?.build(),
            tagRemoves: _tagRemoves?.build(),
            unofficial: unofficial,
            writeBack: writeBack,
            lock: lock,
            force: force,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'fields';
        _fields?.build();
        _$failedField = 'credits';
        _credits?.build();
        _$failedField = 'lyrics';
        _lyrics?.build();

        _$failedField = 'chapters';
        _chapters?.build();
        _$failedField = 'tagSets';
        _tagSets?.build();
        _$failedField = 'tagRemoves';
        _tagRemoves?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'MetadataCommit',
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
