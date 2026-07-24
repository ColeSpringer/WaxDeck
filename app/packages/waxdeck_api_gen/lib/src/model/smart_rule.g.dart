// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'smart_rule.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SmartRule extends SmartRule {
  @override
  final RuleNode root;
  @override
  final BuiltList<RuleSort>? sorts;
  @override
  final int? limit;
  @override
  final String? limitMode;
  @override
  final int? limitSeed;

  factory _$SmartRule([void Function(SmartRuleBuilder)? updates]) =>
      (SmartRuleBuilder()..update(updates))._build();

  _$SmartRule._({
    required this.root,
    this.sorts,
    this.limit,
    this.limitMode,
    this.limitSeed,
  }) : super._();
  @override
  SmartRule rebuild(void Function(SmartRuleBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SmartRuleBuilder toBuilder() => SmartRuleBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SmartRule &&
        root == other.root &&
        sorts == other.sorts &&
        limit == other.limit &&
        limitMode == other.limitMode &&
        limitSeed == other.limitSeed;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, root.hashCode);
    _$hash = $jc(_$hash, sorts.hashCode);
    _$hash = $jc(_$hash, limit.hashCode);
    _$hash = $jc(_$hash, limitMode.hashCode);
    _$hash = $jc(_$hash, limitSeed.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SmartRule')
          ..add('root', root)
          ..add('sorts', sorts)
          ..add('limit', limit)
          ..add('limitMode', limitMode)
          ..add('limitSeed', limitSeed))
        .toString();
  }
}

class SmartRuleBuilder implements Builder<SmartRule, SmartRuleBuilder> {
  _$SmartRule? _$v;

  RuleNodeBuilder? _root;
  RuleNodeBuilder get root => _$this._root ??= RuleNodeBuilder();
  set root(RuleNodeBuilder? root) => _$this._root = root;

  ListBuilder<RuleSort>? _sorts;
  ListBuilder<RuleSort> get sorts => _$this._sorts ??= ListBuilder<RuleSort>();
  set sorts(ListBuilder<RuleSort>? sorts) => _$this._sorts = sorts;

  int? _limit;
  int? get limit => _$this._limit;
  set limit(int? limit) => _$this._limit = limit;

  String? _limitMode;
  String? get limitMode => _$this._limitMode;
  set limitMode(String? limitMode) => _$this._limitMode = limitMode;

  int? _limitSeed;
  int? get limitSeed => _$this._limitSeed;
  set limitSeed(int? limitSeed) => _$this._limitSeed = limitSeed;

  SmartRuleBuilder() {
    SmartRule._defaults(this);
  }

  SmartRuleBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _root = $v.root.toBuilder();
      _sorts = $v.sorts?.toBuilder();
      _limit = $v.limit;
      _limitMode = $v.limitMode;
      _limitSeed = $v.limitSeed;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SmartRule other) {
    _$v = other as _$SmartRule;
  }

  @override
  void update(void Function(SmartRuleBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SmartRule build() => _build();

  _$SmartRule _build() {
    _$SmartRule _$result;
    try {
      _$result =
          _$v ??
          _$SmartRule._(
            root: root.build(),
            sorts: _sorts?.build(),
            limit: limit,
            limitMode: limitMode,
            limitSeed: limitSeed,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'root';
        root.build();
        _$failedField = 'sorts';
        _sorts?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SmartRule',
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
