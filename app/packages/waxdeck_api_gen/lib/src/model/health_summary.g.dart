// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_summary.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HealthSummary extends HealthSummary {
  @override
  final double score;
  @override
  final int totalItems;
  @override
  final int evaluatedItems;
  @override
  final bool warmingUp;
  @override
  final DateTime? sweptAt;
  @override
  final BuiltList<HealthRuleCount> rules;

  factory _$HealthSummary([void Function(HealthSummaryBuilder)? updates]) =>
      (HealthSummaryBuilder()..update(updates))._build();

  _$HealthSummary._({
    required this.score,
    required this.totalItems,
    required this.evaluatedItems,
    required this.warmingUp,
    this.sweptAt,
    required this.rules,
  }) : super._();
  @override
  HealthSummary rebuild(void Function(HealthSummaryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthSummaryBuilder toBuilder() => HealthSummaryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthSummary &&
        score == other.score &&
        totalItems == other.totalItems &&
        evaluatedItems == other.evaluatedItems &&
        warmingUp == other.warmingUp &&
        sweptAt == other.sweptAt &&
        rules == other.rules;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, score.hashCode);
    _$hash = $jc(_$hash, totalItems.hashCode);
    _$hash = $jc(_$hash, evaluatedItems.hashCode);
    _$hash = $jc(_$hash, warmingUp.hashCode);
    _$hash = $jc(_$hash, sweptAt.hashCode);
    _$hash = $jc(_$hash, rules.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthSummary')
          ..add('score', score)
          ..add('totalItems', totalItems)
          ..add('evaluatedItems', evaluatedItems)
          ..add('warmingUp', warmingUp)
          ..add('sweptAt', sweptAt)
          ..add('rules', rules))
        .toString();
  }
}

class HealthSummaryBuilder
    implements Builder<HealthSummary, HealthSummaryBuilder> {
  _$HealthSummary? _$v;

  double? _score;
  double? get score => _$this._score;
  set score(double? score) => _$this._score = score;

  int? _totalItems;
  int? get totalItems => _$this._totalItems;
  set totalItems(int? totalItems) => _$this._totalItems = totalItems;

  int? _evaluatedItems;
  int? get evaluatedItems => _$this._evaluatedItems;
  set evaluatedItems(int? evaluatedItems) =>
      _$this._evaluatedItems = evaluatedItems;

  bool? _warmingUp;
  bool? get warmingUp => _$this._warmingUp;
  set warmingUp(bool? warmingUp) => _$this._warmingUp = warmingUp;

  DateTime? _sweptAt;
  DateTime? get sweptAt => _$this._sweptAt;
  set sweptAt(DateTime? sweptAt) => _$this._sweptAt = sweptAt;

  ListBuilder<HealthRuleCount>? _rules;
  ListBuilder<HealthRuleCount> get rules =>
      _$this._rules ??= ListBuilder<HealthRuleCount>();
  set rules(ListBuilder<HealthRuleCount>? rules) => _$this._rules = rules;

  HealthSummaryBuilder() {
    HealthSummary._defaults(this);
  }

  HealthSummaryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _score = $v.score;
      _totalItems = $v.totalItems;
      _evaluatedItems = $v.evaluatedItems;
      _warmingUp = $v.warmingUp;
      _sweptAt = $v.sweptAt;
      _rules = $v.rules.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthSummary other) {
    _$v = other as _$HealthSummary;
  }

  @override
  void update(void Function(HealthSummaryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthSummary build() => _build();

  _$HealthSummary _build() {
    _$HealthSummary _$result;
    try {
      _$result =
          _$v ??
          _$HealthSummary._(
            score: BuiltValueNullFieldError.checkNotNull(
              score,
              r'HealthSummary',
              'score',
            ),
            totalItems: BuiltValueNullFieldError.checkNotNull(
              totalItems,
              r'HealthSummary',
              'totalItems',
            ),
            evaluatedItems: BuiltValueNullFieldError.checkNotNull(
              evaluatedItems,
              r'HealthSummary',
              'evaluatedItems',
            ),
            warmingUp: BuiltValueNullFieldError.checkNotNull(
              warmingUp,
              r'HealthSummary',
              'warmingUp',
            ),
            sweptAt: sweptAt,
            rules: rules.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'rules';
        rules.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'HealthSummary',
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
