// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rule_sort.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RuleSort extends RuleSort {
  @override
  final String field;
  @override
  final bool? desc;

  factory _$RuleSort([void Function(RuleSortBuilder)? updates]) =>
      (RuleSortBuilder()..update(updates))._build();

  _$RuleSort._({required this.field, this.desc}) : super._();
  @override
  RuleSort rebuild(void Function(RuleSortBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RuleSortBuilder toBuilder() => RuleSortBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RuleSort && field == other.field && desc == other.desc;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, field.hashCode);
    _$hash = $jc(_$hash, desc.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RuleSort')
          ..add('field', field)
          ..add('desc', desc))
        .toString();
  }
}

class RuleSortBuilder implements Builder<RuleSort, RuleSortBuilder> {
  _$RuleSort? _$v;

  String? _field;
  String? get field => _$this._field;
  set field(String? field) => _$this._field = field;

  bool? _desc;
  bool? get desc => _$this._desc;
  set desc(bool? desc) => _$this._desc = desc;

  RuleSortBuilder() {
    RuleSort._defaults(this);
  }

  RuleSortBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _field = $v.field;
      _desc = $v.desc;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RuleSort other) {
    _$v = other as _$RuleSort;
  }

  @override
  void update(void Function(RuleSortBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RuleSort build() => _build();

  _$RuleSort _build() {
    final _$result =
        _$v ??
        _$RuleSort._(
          field: BuiltValueNullFieldError.checkNotNull(
            field,
            r'RuleSort',
            'field',
          ),
          desc: desc,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
