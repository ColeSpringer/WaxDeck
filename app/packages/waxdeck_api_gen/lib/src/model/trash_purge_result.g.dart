// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trash_purge_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TrashPurgeResult extends TrashPurgeResult {
  @override
  final int reclaimedBytes;

  factory _$TrashPurgeResult([
    void Function(TrashPurgeResultBuilder)? updates,
  ]) => (TrashPurgeResultBuilder()..update(updates))._build();

  _$TrashPurgeResult._({required this.reclaimedBytes}) : super._();
  @override
  TrashPurgeResult rebuild(void Function(TrashPurgeResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TrashPurgeResultBuilder toBuilder() =>
      TrashPurgeResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TrashPurgeResult && reclaimedBytes == other.reclaimedBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, reclaimedBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'TrashPurgeResult',
    )..add('reclaimedBytes', reclaimedBytes)).toString();
  }
}

class TrashPurgeResultBuilder
    implements Builder<TrashPurgeResult, TrashPurgeResultBuilder> {
  _$TrashPurgeResult? _$v;

  int? _reclaimedBytes;
  int? get reclaimedBytes => _$this._reclaimedBytes;
  set reclaimedBytes(int? reclaimedBytes) =>
      _$this._reclaimedBytes = reclaimedBytes;

  TrashPurgeResultBuilder() {
    TrashPurgeResult._defaults(this);
  }

  TrashPurgeResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _reclaimedBytes = $v.reclaimedBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TrashPurgeResult other) {
    _$v = other as _$TrashPurgeResult;
  }

  @override
  void update(void Function(TrashPurgeResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TrashPurgeResult build() => _build();

  _$TrashPurgeResult _build() {
    final _$result =
        _$v ??
        _$TrashPurgeResult._(
          reclaimedBytes: BuiltValueNullFieldError.checkNotNull(
            reclaimedBytes,
            r'TrashPurgeResult',
            'reclaimedBytes',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
