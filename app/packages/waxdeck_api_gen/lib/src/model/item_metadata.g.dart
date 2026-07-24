// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item_metadata.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ItemMetadata extends ItemMetadata {
  @override
  final String pid;
  @override
  final MediaType mediaType;
  @override
  final BuiltMap<String, String> fields;
  @override
  final BuiltList<String> lockedFields;
  @override
  final BuiltList<FieldProvenance> provenance;
  @override
  final BuiltList<Credit> credits;
  @override
  final LyricsState? lyrics;
  @override
  final BuiltList<ChapterMark>? chapters;
  @override
  final BuiltList<CustomTag> customTags;
  @override
  final bool unofficial;
  @override
  final bool virtualTrack;
  @override
  final bool hasArtwork;
  @override
  final bool hasOwnArtwork;
  @override
  final String? albumPid;
  @override
  final String? artistPid;
  @override
  final String? releaseGroupPid;
  @override
  final BuiltList<WriteBackIssue> writeBackIssues;

  factory _$ItemMetadata([void Function(ItemMetadataBuilder)? updates]) =>
      (ItemMetadataBuilder()..update(updates))._build();

  _$ItemMetadata._({
    required this.pid,
    required this.mediaType,
    required this.fields,
    required this.lockedFields,
    required this.provenance,
    required this.credits,
    this.lyrics,
    this.chapters,
    required this.customTags,
    required this.unofficial,
    required this.virtualTrack,
    required this.hasArtwork,
    required this.hasOwnArtwork,
    this.albumPid,
    this.artistPid,
    this.releaseGroupPid,
    required this.writeBackIssues,
  }) : super._();
  @override
  ItemMetadata rebuild(void Function(ItemMetadataBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ItemMetadataBuilder toBuilder() => ItemMetadataBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ItemMetadata &&
        pid == other.pid &&
        mediaType == other.mediaType &&
        fields == other.fields &&
        lockedFields == other.lockedFields &&
        provenance == other.provenance &&
        credits == other.credits &&
        lyrics == other.lyrics &&
        chapters == other.chapters &&
        customTags == other.customTags &&
        unofficial == other.unofficial &&
        virtualTrack == other.virtualTrack &&
        hasArtwork == other.hasArtwork &&
        hasOwnArtwork == other.hasOwnArtwork &&
        albumPid == other.albumPid &&
        artistPid == other.artistPid &&
        releaseGroupPid == other.releaseGroupPid &&
        writeBackIssues == other.writeBackIssues;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, fields.hashCode);
    _$hash = $jc(_$hash, lockedFields.hashCode);
    _$hash = $jc(_$hash, provenance.hashCode);
    _$hash = $jc(_$hash, credits.hashCode);
    _$hash = $jc(_$hash, lyrics.hashCode);
    _$hash = $jc(_$hash, chapters.hashCode);
    _$hash = $jc(_$hash, customTags.hashCode);
    _$hash = $jc(_$hash, unofficial.hashCode);
    _$hash = $jc(_$hash, virtualTrack.hashCode);
    _$hash = $jc(_$hash, hasArtwork.hashCode);
    _$hash = $jc(_$hash, hasOwnArtwork.hashCode);
    _$hash = $jc(_$hash, albumPid.hashCode);
    _$hash = $jc(_$hash, artistPid.hashCode);
    _$hash = $jc(_$hash, releaseGroupPid.hashCode);
    _$hash = $jc(_$hash, writeBackIssues.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ItemMetadata')
          ..add('pid', pid)
          ..add('mediaType', mediaType)
          ..add('fields', fields)
          ..add('lockedFields', lockedFields)
          ..add('provenance', provenance)
          ..add('credits', credits)
          ..add('lyrics', lyrics)
          ..add('chapters', chapters)
          ..add('customTags', customTags)
          ..add('unofficial', unofficial)
          ..add('virtualTrack', virtualTrack)
          ..add('hasArtwork', hasArtwork)
          ..add('hasOwnArtwork', hasOwnArtwork)
          ..add('albumPid', albumPid)
          ..add('artistPid', artistPid)
          ..add('releaseGroupPid', releaseGroupPid)
          ..add('writeBackIssues', writeBackIssues))
        .toString();
  }
}

class ItemMetadataBuilder
    implements Builder<ItemMetadata, ItemMetadataBuilder> {
  _$ItemMetadata? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  MediaType? _mediaType;
  MediaType? get mediaType => _$this._mediaType;
  set mediaType(MediaType? mediaType) => _$this._mediaType = mediaType;

  MapBuilder<String, String>? _fields;
  MapBuilder<String, String> get fields =>
      _$this._fields ??= MapBuilder<String, String>();
  set fields(MapBuilder<String, String>? fields) => _$this._fields = fields;

  ListBuilder<String>? _lockedFields;
  ListBuilder<String> get lockedFields =>
      _$this._lockedFields ??= ListBuilder<String>();
  set lockedFields(ListBuilder<String>? lockedFields) =>
      _$this._lockedFields = lockedFields;

  ListBuilder<FieldProvenance>? _provenance;
  ListBuilder<FieldProvenance> get provenance =>
      _$this._provenance ??= ListBuilder<FieldProvenance>();
  set provenance(ListBuilder<FieldProvenance>? provenance) =>
      _$this._provenance = provenance;

  ListBuilder<Credit>? _credits;
  ListBuilder<Credit> get credits => _$this._credits ??= ListBuilder<Credit>();
  set credits(ListBuilder<Credit>? credits) => _$this._credits = credits;

  LyricsStateBuilder? _lyrics;
  LyricsStateBuilder get lyrics => _$this._lyrics ??= LyricsStateBuilder();
  set lyrics(LyricsStateBuilder? lyrics) => _$this._lyrics = lyrics;

  ListBuilder<ChapterMark>? _chapters;
  ListBuilder<ChapterMark> get chapters =>
      _$this._chapters ??= ListBuilder<ChapterMark>();
  set chapters(ListBuilder<ChapterMark>? chapters) =>
      _$this._chapters = chapters;

  ListBuilder<CustomTag>? _customTags;
  ListBuilder<CustomTag> get customTags =>
      _$this._customTags ??= ListBuilder<CustomTag>();
  set customTags(ListBuilder<CustomTag>? customTags) =>
      _$this._customTags = customTags;

  bool? _unofficial;
  bool? get unofficial => _$this._unofficial;
  set unofficial(bool? unofficial) => _$this._unofficial = unofficial;

  bool? _virtualTrack;
  bool? get virtualTrack => _$this._virtualTrack;
  set virtualTrack(bool? virtualTrack) => _$this._virtualTrack = virtualTrack;

  bool? _hasArtwork;
  bool? get hasArtwork => _$this._hasArtwork;
  set hasArtwork(bool? hasArtwork) => _$this._hasArtwork = hasArtwork;

  bool? _hasOwnArtwork;
  bool? get hasOwnArtwork => _$this._hasOwnArtwork;
  set hasOwnArtwork(bool? hasOwnArtwork) =>
      _$this._hasOwnArtwork = hasOwnArtwork;

  String? _albumPid;
  String? get albumPid => _$this._albumPid;
  set albumPid(String? albumPid) => _$this._albumPid = albumPid;

  String? _artistPid;
  String? get artistPid => _$this._artistPid;
  set artistPid(String? artistPid) => _$this._artistPid = artistPid;

  String? _releaseGroupPid;
  String? get releaseGroupPid => _$this._releaseGroupPid;
  set releaseGroupPid(String? releaseGroupPid) =>
      _$this._releaseGroupPid = releaseGroupPid;

  ListBuilder<WriteBackIssue>? _writeBackIssues;
  ListBuilder<WriteBackIssue> get writeBackIssues =>
      _$this._writeBackIssues ??= ListBuilder<WriteBackIssue>();
  set writeBackIssues(ListBuilder<WriteBackIssue>? writeBackIssues) =>
      _$this._writeBackIssues = writeBackIssues;

  ItemMetadataBuilder() {
    ItemMetadata._defaults(this);
  }

  ItemMetadataBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _mediaType = $v.mediaType;
      _fields = $v.fields.toBuilder();
      _lockedFields = $v.lockedFields.toBuilder();
      _provenance = $v.provenance.toBuilder();
      _credits = $v.credits.toBuilder();
      _lyrics = $v.lyrics?.toBuilder();
      _chapters = $v.chapters?.toBuilder();
      _customTags = $v.customTags.toBuilder();
      _unofficial = $v.unofficial;
      _virtualTrack = $v.virtualTrack;
      _hasArtwork = $v.hasArtwork;
      _hasOwnArtwork = $v.hasOwnArtwork;
      _albumPid = $v.albumPid;
      _artistPid = $v.artistPid;
      _releaseGroupPid = $v.releaseGroupPid;
      _writeBackIssues = $v.writeBackIssues.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ItemMetadata other) {
    _$v = other as _$ItemMetadata;
  }

  @override
  void update(void Function(ItemMetadataBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ItemMetadata build() => _build();

  _$ItemMetadata _build() {
    _$ItemMetadata _$result;
    try {
      _$result =
          _$v ??
          _$ItemMetadata._(
            pid: BuiltValueNullFieldError.checkNotNull(
              pid,
              r'ItemMetadata',
              'pid',
            ),
            mediaType: BuiltValueNullFieldError.checkNotNull(
              mediaType,
              r'ItemMetadata',
              'mediaType',
            ),
            fields: fields.build(),
            lockedFields: lockedFields.build(),
            provenance: provenance.build(),
            credits: credits.build(),
            lyrics: _lyrics?.build(),
            chapters: _chapters?.build(),
            customTags: customTags.build(),
            unofficial: BuiltValueNullFieldError.checkNotNull(
              unofficial,
              r'ItemMetadata',
              'unofficial',
            ),
            virtualTrack: BuiltValueNullFieldError.checkNotNull(
              virtualTrack,
              r'ItemMetadata',
              'virtualTrack',
            ),
            hasArtwork: BuiltValueNullFieldError.checkNotNull(
              hasArtwork,
              r'ItemMetadata',
              'hasArtwork',
            ),
            hasOwnArtwork: BuiltValueNullFieldError.checkNotNull(
              hasOwnArtwork,
              r'ItemMetadata',
              'hasOwnArtwork',
            ),
            albumPid: albumPid,
            artistPid: artistPid,
            releaseGroupPid: releaseGroupPid,
            writeBackIssues: writeBackIssues.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'fields';
        fields.build();
        _$failedField = 'lockedFields';
        lockedFields.build();
        _$failedField = 'provenance';
        provenance.build();
        _$failedField = 'credits';
        credits.build();
        _$failedField = 'lyrics';
        _lyrics?.build();
        _$failedField = 'chapters';
        _chapters?.build();
        _$failedField = 'customTags';
        customTags.build();

        _$failedField = 'writeBackIssues';
        writeBackIssues.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ItemMetadata',
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
