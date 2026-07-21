// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadCreate extends UploadCreate {
  @override
  final String fileName;
  @override
  final int sizeBytes;
  @override
  final MediaType mediaType;
  @override
  final String? libraryPid;
  @override
  final String? sha256;

  factory _$UploadCreate([void Function(UploadCreateBuilder)? updates]) =>
      (UploadCreateBuilder()..update(updates))._build();

  _$UploadCreate._({
    required this.fileName,
    required this.sizeBytes,
    required this.mediaType,
    this.libraryPid,
    this.sha256,
  }) : super._();
  @override
  UploadCreate rebuild(void Function(UploadCreateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadCreateBuilder toBuilder() => UploadCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadCreate &&
        fileName == other.fileName &&
        sizeBytes == other.sizeBytes &&
        mediaType == other.mediaType &&
        libraryPid == other.libraryPid &&
        sha256 == other.sha256;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, fileName.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, libraryPid.hashCode);
    _$hash = $jc(_$hash, sha256.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UploadCreate')
          ..add('fileName', fileName)
          ..add('sizeBytes', sizeBytes)
          ..add('mediaType', mediaType)
          ..add('libraryPid', libraryPid)
          ..add('sha256', sha256))
        .toString();
  }
}

class UploadCreateBuilder
    implements Builder<UploadCreate, UploadCreateBuilder> {
  _$UploadCreate? _$v;

  String? _fileName;
  String? get fileName => _$this._fileName;
  set fileName(String? fileName) => _$this._fileName = fileName;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  MediaType? _mediaType;
  MediaType? get mediaType => _$this._mediaType;
  set mediaType(MediaType? mediaType) => _$this._mediaType = mediaType;

  String? _libraryPid;
  String? get libraryPid => _$this._libraryPid;
  set libraryPid(String? libraryPid) => _$this._libraryPid = libraryPid;

  String? _sha256;
  String? get sha256 => _$this._sha256;
  set sha256(String? sha256) => _$this._sha256 = sha256;

  UploadCreateBuilder() {
    UploadCreate._defaults(this);
  }

  UploadCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _fileName = $v.fileName;
      _sizeBytes = $v.sizeBytes;
      _mediaType = $v.mediaType;
      _libraryPid = $v.libraryPid;
      _sha256 = $v.sha256;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadCreate other) {
    _$v = other as _$UploadCreate;
  }

  @override
  void update(void Function(UploadCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadCreate build() => _build();

  _$UploadCreate _build() {
    final _$result =
        _$v ??
        _$UploadCreate._(
          fileName: BuiltValueNullFieldError.checkNotNull(
            fileName,
            r'UploadCreate',
            'fileName',
          ),
          sizeBytes: BuiltValueNullFieldError.checkNotNull(
            sizeBytes,
            r'UploadCreate',
            'sizeBytes',
          ),
          mediaType: BuiltValueNullFieldError.checkNotNull(
            mediaType,
            r'UploadCreate',
            'mediaType',
          ),
          libraryPid: libraryPid,
          sha256: sha256,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
