// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_batch_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadBatchCreate extends UploadBatchCreate {
  @override
  final UploadGrouping grouping;
  @override
  final MediaType mediaType;
  @override
  final String? libraryPid;
  @override
  final bool? identify;

  factory _$UploadBatchCreate([
    void Function(UploadBatchCreateBuilder)? updates,
  ]) => (UploadBatchCreateBuilder()..update(updates))._build();

  _$UploadBatchCreate._({
    required this.grouping,
    required this.mediaType,
    this.libraryPid,
    this.identify,
  }) : super._();
  @override
  UploadBatchCreate rebuild(void Function(UploadBatchCreateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadBatchCreateBuilder toBuilder() =>
      UploadBatchCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadBatchCreate &&
        grouping == other.grouping &&
        mediaType == other.mediaType &&
        libraryPid == other.libraryPid &&
        identify == other.identify;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, grouping.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, libraryPid.hashCode);
    _$hash = $jc(_$hash, identify.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UploadBatchCreate')
          ..add('grouping', grouping)
          ..add('mediaType', mediaType)
          ..add('libraryPid', libraryPid)
          ..add('identify', identify))
        .toString();
  }
}

class UploadBatchCreateBuilder
    implements Builder<UploadBatchCreate, UploadBatchCreateBuilder> {
  _$UploadBatchCreate? _$v;

  UploadGrouping? _grouping;
  UploadGrouping? get grouping => _$this._grouping;
  set grouping(UploadGrouping? grouping) => _$this._grouping = grouping;

  MediaType? _mediaType;
  MediaType? get mediaType => _$this._mediaType;
  set mediaType(MediaType? mediaType) => _$this._mediaType = mediaType;

  String? _libraryPid;
  String? get libraryPid => _$this._libraryPid;
  set libraryPid(String? libraryPid) => _$this._libraryPid = libraryPid;

  bool? _identify;
  bool? get identify => _$this._identify;
  set identify(bool? identify) => _$this._identify = identify;

  UploadBatchCreateBuilder() {
    UploadBatchCreate._defaults(this);
  }

  UploadBatchCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _grouping = $v.grouping;
      _mediaType = $v.mediaType;
      _libraryPid = $v.libraryPid;
      _identify = $v.identify;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadBatchCreate other) {
    _$v = other as _$UploadBatchCreate;
  }

  @override
  void update(void Function(UploadBatchCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadBatchCreate build() => _build();

  _$UploadBatchCreate _build() {
    final _$result =
        _$v ??
        _$UploadBatchCreate._(
          grouping: BuiltValueNullFieldError.checkNotNull(
            grouping,
            r'UploadBatchCreate',
            'grouping',
          ),
          mediaType: BuiltValueNullFieldError.checkNotNull(
            mediaType,
            r'UploadBatchCreate',
            'mediaType',
          ),
          libraryPid: libraryPid,
          identify: identify,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
