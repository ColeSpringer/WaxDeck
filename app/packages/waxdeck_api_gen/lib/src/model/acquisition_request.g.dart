// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acquisition_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AcquisitionRequest extends AcquisitionRequest {
  @override
  final String url;
  @override
  final MediaType mediaType;
  @override
  final String? libraryPid;
  @override
  final AcquisitionFormat? format;

  factory _$AcquisitionRequest([
    void Function(AcquisitionRequestBuilder)? updates,
  ]) => (AcquisitionRequestBuilder()..update(updates))._build();

  _$AcquisitionRequest._({
    required this.url,
    required this.mediaType,
    this.libraryPid,
    this.format,
  }) : super._();
  @override
  AcquisitionRequest rebuild(
    void Function(AcquisitionRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  AcquisitionRequestBuilder toBuilder() =>
      AcquisitionRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AcquisitionRequest &&
        url == other.url &&
        mediaType == other.mediaType &&
        libraryPid == other.libraryPid &&
        format == other.format;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, libraryPid.hashCode);
    _$hash = $jc(_$hash, format.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AcquisitionRequest')
          ..add('url', url)
          ..add('mediaType', mediaType)
          ..add('libraryPid', libraryPid)
          ..add('format', format))
        .toString();
  }
}

class AcquisitionRequestBuilder
    implements Builder<AcquisitionRequest, AcquisitionRequestBuilder> {
  _$AcquisitionRequest? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  MediaType? _mediaType;
  MediaType? get mediaType => _$this._mediaType;
  set mediaType(MediaType? mediaType) => _$this._mediaType = mediaType;

  String? _libraryPid;
  String? get libraryPid => _$this._libraryPid;
  set libraryPid(String? libraryPid) => _$this._libraryPid = libraryPid;

  AcquisitionFormat? _format;
  AcquisitionFormat? get format => _$this._format;
  set format(AcquisitionFormat? format) => _$this._format = format;

  AcquisitionRequestBuilder() {
    AcquisitionRequest._defaults(this);
  }

  AcquisitionRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _mediaType = $v.mediaType;
      _libraryPid = $v.libraryPid;
      _format = $v.format;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AcquisitionRequest other) {
    _$v = other as _$AcquisitionRequest;
  }

  @override
  void update(void Function(AcquisitionRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AcquisitionRequest build() => _build();

  _$AcquisitionRequest _build() {
    final _$result =
        _$v ??
        _$AcquisitionRequest._(
          url: BuiltValueNullFieldError.checkNotNull(
            url,
            r'AcquisitionRequest',
            'url',
          ),
          mediaType: BuiltValueNullFieldError.checkNotNull(
            mediaType,
            r'AcquisitionRequest',
            'mediaType',
          ),
          libraryPid: libraryPid,
          format: format,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
