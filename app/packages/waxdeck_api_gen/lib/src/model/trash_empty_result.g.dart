// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trash_empty_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TrashEmptyResult extends TrashEmptyResult {
  @override
  final int purged;
  @override
  final int errored;
  @override
  final int reclaimedBytes;

  factory _$TrashEmptyResult([
    void Function(TrashEmptyResultBuilder)? updates,
  ]) => (TrashEmptyResultBuilder()..update(updates))._build();

  _$TrashEmptyResult._({
    required this.purged,
    required this.errored,
    required this.reclaimedBytes,
  }) : super._();
  @override
  TrashEmptyResult rebuild(void Function(TrashEmptyResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TrashEmptyResultBuilder toBuilder() =>
      TrashEmptyResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TrashEmptyResult &&
        purged == other.purged &&
        errored == other.errored &&
        reclaimedBytes == other.reclaimedBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, purged.hashCode);
    _$hash = $jc(_$hash, errored.hashCode);
    _$hash = $jc(_$hash, reclaimedBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TrashEmptyResult')
          ..add('purged', purged)
          ..add('errored', errored)
          ..add('reclaimedBytes', reclaimedBytes))
        .toString();
  }
}

class TrashEmptyResultBuilder
    implements Builder<TrashEmptyResult, TrashEmptyResultBuilder> {
  _$TrashEmptyResult? _$v;

  int? _purged;
  int? get purged => _$this._purged;
  set purged(int? purged) => _$this._purged = purged;

  int? _errored;
  int? get errored => _$this._errored;
  set errored(int? errored) => _$this._errored = errored;

  int? _reclaimedBytes;
  int? get reclaimedBytes => _$this._reclaimedBytes;
  set reclaimedBytes(int? reclaimedBytes) =>
      _$this._reclaimedBytes = reclaimedBytes;

  TrashEmptyResultBuilder() {
    TrashEmptyResult._defaults(this);
  }

  TrashEmptyResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _purged = $v.purged;
      _errored = $v.errored;
      _reclaimedBytes = $v.reclaimedBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TrashEmptyResult other) {
    _$v = other as _$TrashEmptyResult;
  }

  @override
  void update(void Function(TrashEmptyResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TrashEmptyResult build() => _build();

  _$TrashEmptyResult _build() {
    final _$result =
        _$v ??
        _$TrashEmptyResult._(
          purged: BuiltValueNullFieldError.checkNotNull(
            purged,
            r'TrashEmptyResult',
            'purged',
          ),
          errored: BuiltValueNullFieldError.checkNotNull(
            errored,
            r'TrashEmptyResult',
            'errored',
          ),
          reclaimedBytes: BuiltValueNullFieldError.checkNotNull(
            reclaimedBytes,
            r'TrashEmptyResult',
            'reclaimedBytes',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
