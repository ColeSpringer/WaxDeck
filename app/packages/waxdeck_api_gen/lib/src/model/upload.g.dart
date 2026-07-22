// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Upload extends Upload {
  @override
  final String id;
  @override
  final String fileName;
  @override
  final int sizeBytes;
  @override
  final int receivedBytes;
  @override
  final MediaType mediaType;
  @override
  final String? libraryPid;
  @override
  final String state;
  @override
  final String? reviewEntryId;
  @override
  final String? batchId;
  @override
  final DuplicateWarning? duplicate;
  @override
  final String? uploadedBy;
  @override
  final DateTime createdAt;
  @override
  final DateTime? expiresAt;

  factory _$Upload([void Function(UploadBuilder)? updates]) =>
      (UploadBuilder()..update(updates))._build();

  _$Upload._({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.receivedBytes,
    required this.mediaType,
    this.libraryPid,
    required this.state,
    this.reviewEntryId,
    this.batchId,
    this.duplicate,
    this.uploadedBy,
    required this.createdAt,
    this.expiresAt,
  }) : super._();
  @override
  Upload rebuild(void Function(UploadBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadBuilder toBuilder() => UploadBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Upload &&
        id == other.id &&
        fileName == other.fileName &&
        sizeBytes == other.sizeBytes &&
        receivedBytes == other.receivedBytes &&
        mediaType == other.mediaType &&
        libraryPid == other.libraryPid &&
        state == other.state &&
        reviewEntryId == other.reviewEntryId &&
        batchId == other.batchId &&
        duplicate == other.duplicate &&
        uploadedBy == other.uploadedBy &&
        createdAt == other.createdAt &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, fileName.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, receivedBytes.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, libraryPid.hashCode);
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, reviewEntryId.hashCode);
    _$hash = $jc(_$hash, batchId.hashCode);
    _$hash = $jc(_$hash, duplicate.hashCode);
    _$hash = $jc(_$hash, uploadedBy.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Upload')
          ..add('id', id)
          ..add('fileName', fileName)
          ..add('sizeBytes', sizeBytes)
          ..add('receivedBytes', receivedBytes)
          ..add('mediaType', mediaType)
          ..add('libraryPid', libraryPid)
          ..add('state', state)
          ..add('reviewEntryId', reviewEntryId)
          ..add('batchId', batchId)
          ..add('duplicate', duplicate)
          ..add('uploadedBy', uploadedBy)
          ..add('createdAt', createdAt)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class UploadBuilder implements Builder<Upload, UploadBuilder> {
  _$Upload? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _fileName;
  String? get fileName => _$this._fileName;
  set fileName(String? fileName) => _$this._fileName = fileName;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  int? _receivedBytes;
  int? get receivedBytes => _$this._receivedBytes;
  set receivedBytes(int? receivedBytes) =>
      _$this._receivedBytes = receivedBytes;

  MediaType? _mediaType;
  MediaType? get mediaType => _$this._mediaType;
  set mediaType(MediaType? mediaType) => _$this._mediaType = mediaType;

  String? _libraryPid;
  String? get libraryPid => _$this._libraryPid;
  set libraryPid(String? libraryPid) => _$this._libraryPid = libraryPid;

  String? _state;
  String? get state => _$this._state;
  set state(String? state) => _$this._state = state;

  String? _reviewEntryId;
  String? get reviewEntryId => _$this._reviewEntryId;
  set reviewEntryId(String? reviewEntryId) =>
      _$this._reviewEntryId = reviewEntryId;

  String? _batchId;
  String? get batchId => _$this._batchId;
  set batchId(String? batchId) => _$this._batchId = batchId;

  DuplicateWarningBuilder? _duplicate;
  DuplicateWarningBuilder get duplicate =>
      _$this._duplicate ??= DuplicateWarningBuilder();
  set duplicate(DuplicateWarningBuilder? duplicate) =>
      _$this._duplicate = duplicate;

  String? _uploadedBy;
  String? get uploadedBy => _$this._uploadedBy;
  set uploadedBy(String? uploadedBy) => _$this._uploadedBy = uploadedBy;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  UploadBuilder() {
    Upload._defaults(this);
  }

  UploadBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _fileName = $v.fileName;
      _sizeBytes = $v.sizeBytes;
      _receivedBytes = $v.receivedBytes;
      _mediaType = $v.mediaType;
      _libraryPid = $v.libraryPid;
      _state = $v.state;
      _reviewEntryId = $v.reviewEntryId;
      _batchId = $v.batchId;
      _duplicate = $v.duplicate?.toBuilder();
      _uploadedBy = $v.uploadedBy;
      _createdAt = $v.createdAt;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Upload other) {
    _$v = other as _$Upload;
  }

  @override
  void update(void Function(UploadBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Upload build() => _build();

  _$Upload _build() {
    _$Upload _$result;
    try {
      _$result =
          _$v ??
          _$Upload._(
            id: BuiltValueNullFieldError.checkNotNull(id, r'Upload', 'id'),
            fileName: BuiltValueNullFieldError.checkNotNull(
              fileName,
              r'Upload',
              'fileName',
            ),
            sizeBytes: BuiltValueNullFieldError.checkNotNull(
              sizeBytes,
              r'Upload',
              'sizeBytes',
            ),
            receivedBytes: BuiltValueNullFieldError.checkNotNull(
              receivedBytes,
              r'Upload',
              'receivedBytes',
            ),
            mediaType: BuiltValueNullFieldError.checkNotNull(
              mediaType,
              r'Upload',
              'mediaType',
            ),
            libraryPid: libraryPid,
            state: BuiltValueNullFieldError.checkNotNull(
              state,
              r'Upload',
              'state',
            ),
            reviewEntryId: reviewEntryId,
            batchId: batchId,
            duplicate: _duplicate?.build(),
            uploadedBy: uploadedBy,
            createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt,
              r'Upload',
              'createdAt',
            ),
            expiresAt: expiresAt,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'duplicate';
        _duplicate?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'Upload',
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
