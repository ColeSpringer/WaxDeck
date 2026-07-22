// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'resolve_rung_counts.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ResolveRungCounts extends ResolveRungCounts {
  @override
  final int essence;
  @override
  final int strongId;
  @override
  final int fingerprint;
  @override
  final int descriptive;

  factory _$ResolveRungCounts([
    void Function(ResolveRungCountsBuilder)? updates,
  ]) => (ResolveRungCountsBuilder()..update(updates))._build();

  _$ResolveRungCounts._({
    required this.essence,
    required this.strongId,
    required this.fingerprint,
    required this.descriptive,
  }) : super._();
  @override
  ResolveRungCounts rebuild(void Function(ResolveRungCountsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ResolveRungCountsBuilder toBuilder() =>
      ResolveRungCountsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ResolveRungCounts &&
        essence == other.essence &&
        strongId == other.strongId &&
        fingerprint == other.fingerprint &&
        descriptive == other.descriptive;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, essence.hashCode);
    _$hash = $jc(_$hash, strongId.hashCode);
    _$hash = $jc(_$hash, fingerprint.hashCode);
    _$hash = $jc(_$hash, descriptive.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ResolveRungCounts')
          ..add('essence', essence)
          ..add('strongId', strongId)
          ..add('fingerprint', fingerprint)
          ..add('descriptive', descriptive))
        .toString();
  }
}

class ResolveRungCountsBuilder
    implements Builder<ResolveRungCounts, ResolveRungCountsBuilder> {
  _$ResolveRungCounts? _$v;

  int? _essence;
  int? get essence => _$this._essence;
  set essence(int? essence) => _$this._essence = essence;

  int? _strongId;
  int? get strongId => _$this._strongId;
  set strongId(int? strongId) => _$this._strongId = strongId;

  int? _fingerprint;
  int? get fingerprint => _$this._fingerprint;
  set fingerprint(int? fingerprint) => _$this._fingerprint = fingerprint;

  int? _descriptive;
  int? get descriptive => _$this._descriptive;
  set descriptive(int? descriptive) => _$this._descriptive = descriptive;

  ResolveRungCountsBuilder() {
    ResolveRungCounts._defaults(this);
  }

  ResolveRungCountsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _essence = $v.essence;
      _strongId = $v.strongId;
      _fingerprint = $v.fingerprint;
      _descriptive = $v.descriptive;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ResolveRungCounts other) {
    _$v = other as _$ResolveRungCounts;
  }

  @override
  void update(void Function(ResolveRungCountsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ResolveRungCounts build() => _build();

  _$ResolveRungCounts _build() {
    final _$result =
        _$v ??
        _$ResolveRungCounts._(
          essence: BuiltValueNullFieldError.checkNotNull(
            essence,
            r'ResolveRungCounts',
            'essence',
          ),
          strongId: BuiltValueNullFieldError.checkNotNull(
            strongId,
            r'ResolveRungCounts',
            'strongId',
          ),
          fingerprint: BuiltValueNullFieldError.checkNotNull(
            fingerprint,
            r'ResolveRungCounts',
            'fingerprint',
          ),
          descriptive: BuiltValueNullFieldError.checkNotNull(
            descriptive,
            r'ResolveRungCounts',
            'descriptive',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
