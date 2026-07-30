// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_file.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DownloadFile extends DownloadFile {
  @override
  final String url;
  @override
  final String mimeType;
  @override
  final int sizeBytes;
  @override
  final int? durationMs;
  @override
  final String fileName;
  @override
  final String essenceHash;
  @override
  final String etag;

  factory _$DownloadFile([void Function(DownloadFileBuilder)? updates]) =>
      (DownloadFileBuilder()..update(updates))._build();

  _$DownloadFile._({
    required this.url,
    required this.mimeType,
    required this.sizeBytes,
    this.durationMs,
    required this.fileName,
    required this.essenceHash,
    required this.etag,
  }) : super._();
  @override
  DownloadFile rebuild(void Function(DownloadFileBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DownloadFileBuilder toBuilder() => DownloadFileBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DownloadFile &&
        url == other.url &&
        mimeType == other.mimeType &&
        sizeBytes == other.sizeBytes &&
        durationMs == other.durationMs &&
        fileName == other.fileName &&
        essenceHash == other.essenceHash &&
        etag == other.etag;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, mimeType.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jc(_$hash, fileName.hashCode);
    _$hash = $jc(_$hash, essenceHash.hashCode);
    _$hash = $jc(_$hash, etag.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DownloadFile')
          ..add('url', url)
          ..add('mimeType', mimeType)
          ..add('sizeBytes', sizeBytes)
          ..add('durationMs', durationMs)
          ..add('fileName', fileName)
          ..add('essenceHash', essenceHash)
          ..add('etag', etag))
        .toString();
  }
}

class DownloadFileBuilder
    implements Builder<DownloadFile, DownloadFileBuilder> {
  _$DownloadFile? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _mimeType;
  String? get mimeType => _$this._mimeType;
  set mimeType(String? mimeType) => _$this._mimeType = mimeType;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  String? _fileName;
  String? get fileName => _$this._fileName;
  set fileName(String? fileName) => _$this._fileName = fileName;

  String? _essenceHash;
  String? get essenceHash => _$this._essenceHash;
  set essenceHash(String? essenceHash) => _$this._essenceHash = essenceHash;

  String? _etag;
  String? get etag => _$this._etag;
  set etag(String? etag) => _$this._etag = etag;

  DownloadFileBuilder() {
    DownloadFile._defaults(this);
  }

  DownloadFileBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _mimeType = $v.mimeType;
      _sizeBytes = $v.sizeBytes;
      _durationMs = $v.durationMs;
      _fileName = $v.fileName;
      _essenceHash = $v.essenceHash;
      _etag = $v.etag;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DownloadFile other) {
    _$v = other as _$DownloadFile;
  }

  @override
  void update(void Function(DownloadFileBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DownloadFile build() => _build();

  _$DownloadFile _build() {
    final _$result =
        _$v ??
        _$DownloadFile._(
          url: BuiltValueNullFieldError.checkNotNull(
            url,
            r'DownloadFile',
            'url',
          ),
          mimeType: BuiltValueNullFieldError.checkNotNull(
            mimeType,
            r'DownloadFile',
            'mimeType',
          ),
          sizeBytes: BuiltValueNullFieldError.checkNotNull(
            sizeBytes,
            r'DownloadFile',
            'sizeBytes',
          ),
          durationMs: durationMs,
          fileName: BuiltValueNullFieldError.checkNotNull(
            fileName,
            r'DownloadFile',
            'fileName',
          ),
          essenceHash: BuiltValueNullFieldError.checkNotNull(
            essenceHash,
            r'DownloadFile',
            'essenceHash',
          ),
          etag: BuiltValueNullFieldError.checkNotNull(
            etag,
            r'DownloadFile',
            'etag',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
