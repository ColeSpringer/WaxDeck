// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_quota.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UploadQuota extends UploadQuota {
  @override
  final int bytesInUse;
  @override
  final int? quotaBytes;

  factory _$UploadQuota([void Function(UploadQuotaBuilder)? updates]) =>
      (UploadQuotaBuilder()..update(updates))._build();

  _$UploadQuota._({required this.bytesInUse, this.quotaBytes}) : super._();
  @override
  UploadQuota rebuild(void Function(UploadQuotaBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UploadQuotaBuilder toBuilder() => UploadQuotaBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UploadQuota &&
        bytesInUse == other.bytesInUse &&
        quotaBytes == other.quotaBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bytesInUse.hashCode);
    _$hash = $jc(_$hash, quotaBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UploadQuota')
          ..add('bytesInUse', bytesInUse)
          ..add('quotaBytes', quotaBytes))
        .toString();
  }
}

class UploadQuotaBuilder implements Builder<UploadQuota, UploadQuotaBuilder> {
  _$UploadQuota? _$v;

  int? _bytesInUse;
  int? get bytesInUse => _$this._bytesInUse;
  set bytesInUse(int? bytesInUse) => _$this._bytesInUse = bytesInUse;

  int? _quotaBytes;
  int? get quotaBytes => _$this._quotaBytes;
  set quotaBytes(int? quotaBytes) => _$this._quotaBytes = quotaBytes;

  UploadQuotaBuilder() {
    UploadQuota._defaults(this);
  }

  UploadQuotaBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bytesInUse = $v.bytesInUse;
      _quotaBytes = $v.quotaBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UploadQuota other) {
    _$v = other as _$UploadQuota;
  }

  @override
  void update(void Function(UploadQuotaBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UploadQuota build() => _build();

  _$UploadQuota _build() {
    final _$result =
        _$v ??
        _$UploadQuota._(
          bytesInUse: BuiltValueNullFieldError.checkNotNull(
            bytesInUse,
            r'UploadQuota',
            'bytesInUse',
          ),
          quotaBytes: quotaBytes,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
