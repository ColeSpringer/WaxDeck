// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'restore_plan.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RestorePlan extends RestorePlan {
  @override
  final String backupId;
  @override
  final DateTime stagedAt;
  @override
  final bool keyfilePresent;
  @override
  final bool keyfileMatches;
  @override
  final BuiltList<SealedCasualty> sealedCasualties;
  @override
  final BuiltList<String> warnings;

  factory _$RestorePlan([void Function(RestorePlanBuilder)? updates]) =>
      (RestorePlanBuilder()..update(updates))._build();

  _$RestorePlan._({
    required this.backupId,
    required this.stagedAt,
    required this.keyfilePresent,
    required this.keyfileMatches,
    required this.sealedCasualties,
    required this.warnings,
  }) : super._();
  @override
  RestorePlan rebuild(void Function(RestorePlanBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RestorePlanBuilder toBuilder() => RestorePlanBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RestorePlan &&
        backupId == other.backupId &&
        stagedAt == other.stagedAt &&
        keyfilePresent == other.keyfilePresent &&
        keyfileMatches == other.keyfileMatches &&
        sealedCasualties == other.sealedCasualties &&
        warnings == other.warnings;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, backupId.hashCode);
    _$hash = $jc(_$hash, stagedAt.hashCode);
    _$hash = $jc(_$hash, keyfilePresent.hashCode);
    _$hash = $jc(_$hash, keyfileMatches.hashCode);
    _$hash = $jc(_$hash, sealedCasualties.hashCode);
    _$hash = $jc(_$hash, warnings.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RestorePlan')
          ..add('backupId', backupId)
          ..add('stagedAt', stagedAt)
          ..add('keyfilePresent', keyfilePresent)
          ..add('keyfileMatches', keyfileMatches)
          ..add('sealedCasualties', sealedCasualties)
          ..add('warnings', warnings))
        .toString();
  }
}

class RestorePlanBuilder implements Builder<RestorePlan, RestorePlanBuilder> {
  _$RestorePlan? _$v;

  String? _backupId;
  String? get backupId => _$this._backupId;
  set backupId(String? backupId) => _$this._backupId = backupId;

  DateTime? _stagedAt;
  DateTime? get stagedAt => _$this._stagedAt;
  set stagedAt(DateTime? stagedAt) => _$this._stagedAt = stagedAt;

  bool? _keyfilePresent;
  bool? get keyfilePresent => _$this._keyfilePresent;
  set keyfilePresent(bool? keyfilePresent) =>
      _$this._keyfilePresent = keyfilePresent;

  bool? _keyfileMatches;
  bool? get keyfileMatches => _$this._keyfileMatches;
  set keyfileMatches(bool? keyfileMatches) =>
      _$this._keyfileMatches = keyfileMatches;

  ListBuilder<SealedCasualty>? _sealedCasualties;
  ListBuilder<SealedCasualty> get sealedCasualties =>
      _$this._sealedCasualties ??= ListBuilder<SealedCasualty>();
  set sealedCasualties(ListBuilder<SealedCasualty>? sealedCasualties) =>
      _$this._sealedCasualties = sealedCasualties;

  ListBuilder<String>? _warnings;
  ListBuilder<String> get warnings =>
      _$this._warnings ??= ListBuilder<String>();
  set warnings(ListBuilder<String>? warnings) => _$this._warnings = warnings;

  RestorePlanBuilder() {
    RestorePlan._defaults(this);
  }

  RestorePlanBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _backupId = $v.backupId;
      _stagedAt = $v.stagedAt;
      _keyfilePresent = $v.keyfilePresent;
      _keyfileMatches = $v.keyfileMatches;
      _sealedCasualties = $v.sealedCasualties.toBuilder();
      _warnings = $v.warnings.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RestorePlan other) {
    _$v = other as _$RestorePlan;
  }

  @override
  void update(void Function(RestorePlanBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RestorePlan build() => _build();

  _$RestorePlan _build() {
    _$RestorePlan _$result;
    try {
      _$result =
          _$v ??
          _$RestorePlan._(
            backupId: BuiltValueNullFieldError.checkNotNull(
              backupId,
              r'RestorePlan',
              'backupId',
            ),
            stagedAt: BuiltValueNullFieldError.checkNotNull(
              stagedAt,
              r'RestorePlan',
              'stagedAt',
            ),
            keyfilePresent: BuiltValueNullFieldError.checkNotNull(
              keyfilePresent,
              r'RestorePlan',
              'keyfilePresent',
            ),
            keyfileMatches: BuiltValueNullFieldError.checkNotNull(
              keyfileMatches,
              r'RestorePlan',
              'keyfileMatches',
            ),
            sealedCasualties: sealedCasualties.build(),
            warnings: warnings.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'sealedCasualties';
        sealedCasualties.build();
        _$failedField = 'warnings';
        warnings.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'RestorePlan',
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
