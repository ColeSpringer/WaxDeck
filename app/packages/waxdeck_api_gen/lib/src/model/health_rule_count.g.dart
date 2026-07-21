// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_rule_count.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HealthRuleCount extends HealthRuleCount {
  @override
  final String rule;
  @override
  final String? label;
  @override
  final int failing;
  @override
  final bool fixable;

  factory _$HealthRuleCount([void Function(HealthRuleCountBuilder)? updates]) =>
      (HealthRuleCountBuilder()..update(updates))._build();

  _$HealthRuleCount._({
    required this.rule,
    this.label,
    required this.failing,
    required this.fixable,
  }) : super._();
  @override
  HealthRuleCount rebuild(void Function(HealthRuleCountBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthRuleCountBuilder toBuilder() => HealthRuleCountBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthRuleCount &&
        rule == other.rule &&
        label == other.label &&
        failing == other.failing &&
        fixable == other.fixable;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, rule.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, failing.hashCode);
    _$hash = $jc(_$hash, fixable.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthRuleCount')
          ..add('rule', rule)
          ..add('label', label)
          ..add('failing', failing)
          ..add('fixable', fixable))
        .toString();
  }
}

class HealthRuleCountBuilder
    implements Builder<HealthRuleCount, HealthRuleCountBuilder> {
  _$HealthRuleCount? _$v;

  String? _rule;
  String? get rule => _$this._rule;
  set rule(String? rule) => _$this._rule = rule;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  int? _failing;
  int? get failing => _$this._failing;
  set failing(int? failing) => _$this._failing = failing;

  bool? _fixable;
  bool? get fixable => _$this._fixable;
  set fixable(bool? fixable) => _$this._fixable = fixable;

  HealthRuleCountBuilder() {
    HealthRuleCount._defaults(this);
  }

  HealthRuleCountBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _rule = $v.rule;
      _label = $v.label;
      _failing = $v.failing;
      _fixable = $v.fixable;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthRuleCount other) {
    _$v = other as _$HealthRuleCount;
  }

  @override
  void update(void Function(HealthRuleCountBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthRuleCount build() => _build();

  _$HealthRuleCount _build() {
    final _$result =
        _$v ??
        _$HealthRuleCount._(
          rule: BuiltValueNullFieldError.checkNotNull(
            rule,
            r'HealthRuleCount',
            'rule',
          ),
          label: label,
          failing: BuiltValueNullFieldError.checkNotNull(
            failing,
            r'HealthRuleCount',
            'failing',
          ),
          fixable: BuiltValueNullFieldError.checkNotNull(
            fixable,
            r'HealthRuleCount',
            'fixable',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
