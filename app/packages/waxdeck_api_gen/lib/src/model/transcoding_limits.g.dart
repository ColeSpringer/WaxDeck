// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcoding_limits.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TranscodingLimits extends TranscodingLimits {
  @override
  final int maxConcurrent;
  @override
  final int maxConcurrentPerUser;
  @override
  final int defaultMaxBitrateKbps;

  factory _$TranscodingLimits([
    void Function(TranscodingLimitsBuilder)? updates,
  ]) => (TranscodingLimitsBuilder()..update(updates))._build();

  _$TranscodingLimits._({
    required this.maxConcurrent,
    required this.maxConcurrentPerUser,
    required this.defaultMaxBitrateKbps,
  }) : super._();
  @override
  TranscodingLimits rebuild(void Function(TranscodingLimitsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TranscodingLimitsBuilder toBuilder() =>
      TranscodingLimitsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TranscodingLimits &&
        maxConcurrent == other.maxConcurrent &&
        maxConcurrentPerUser == other.maxConcurrentPerUser &&
        defaultMaxBitrateKbps == other.defaultMaxBitrateKbps;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, maxConcurrent.hashCode);
    _$hash = $jc(_$hash, maxConcurrentPerUser.hashCode);
    _$hash = $jc(_$hash, defaultMaxBitrateKbps.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TranscodingLimits')
          ..add('maxConcurrent', maxConcurrent)
          ..add('maxConcurrentPerUser', maxConcurrentPerUser)
          ..add('defaultMaxBitrateKbps', defaultMaxBitrateKbps))
        .toString();
  }
}

class TranscodingLimitsBuilder
    implements Builder<TranscodingLimits, TranscodingLimitsBuilder> {
  _$TranscodingLimits? _$v;

  int? _maxConcurrent;
  int? get maxConcurrent => _$this._maxConcurrent;
  set maxConcurrent(int? maxConcurrent) =>
      _$this._maxConcurrent = maxConcurrent;

  int? _maxConcurrentPerUser;
  int? get maxConcurrentPerUser => _$this._maxConcurrentPerUser;
  set maxConcurrentPerUser(int? maxConcurrentPerUser) =>
      _$this._maxConcurrentPerUser = maxConcurrentPerUser;

  int? _defaultMaxBitrateKbps;
  int? get defaultMaxBitrateKbps => _$this._defaultMaxBitrateKbps;
  set defaultMaxBitrateKbps(int? defaultMaxBitrateKbps) =>
      _$this._defaultMaxBitrateKbps = defaultMaxBitrateKbps;

  TranscodingLimitsBuilder() {
    TranscodingLimits._defaults(this);
  }

  TranscodingLimitsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _maxConcurrent = $v.maxConcurrent;
      _maxConcurrentPerUser = $v.maxConcurrentPerUser;
      _defaultMaxBitrateKbps = $v.defaultMaxBitrateKbps;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TranscodingLimits other) {
    _$v = other as _$TranscodingLimits;
  }

  @override
  void update(void Function(TranscodingLimitsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TranscodingLimits build() => _build();

  _$TranscodingLimits _build() {
    final _$result =
        _$v ??
        _$TranscodingLimits._(
          maxConcurrent: BuiltValueNullFieldError.checkNotNull(
            maxConcurrent,
            r'TranscodingLimits',
            'maxConcurrent',
          ),
          maxConcurrentPerUser: BuiltValueNullFieldError.checkNotNull(
            maxConcurrentPerUser,
            r'TranscodingLimits',
            'maxConcurrentPerUser',
          ),
          defaultMaxBitrateKbps: BuiltValueNullFieldError.checkNotNull(
            defaultMaxBitrateKbps,
            r'TranscodingLimits',
            'defaultMaxBitrateKbps',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
