// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag_rule.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TagRule extends TagRule {
  @override
  final String key;
  @override
  final String? value;

  factory _$TagRule([void Function(TagRuleBuilder)? updates]) =>
      (TagRuleBuilder()..update(updates))._build();

  _$TagRule._({required this.key, this.value}) : super._();
  @override
  TagRule rebuild(void Function(TagRuleBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TagRuleBuilder toBuilder() => TagRuleBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TagRule && key == other.key && value == other.value;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, key.hashCode);
    _$hash = $jc(_$hash, value.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TagRule')
          ..add('key', key)
          ..add('value', value))
        .toString();
  }
}

class TagRuleBuilder implements Builder<TagRule, TagRuleBuilder> {
  _$TagRule? _$v;

  String? _key;
  String? get key => _$this._key;
  set key(String? key) => _$this._key = key;

  String? _value;
  String? get value => _$this._value;
  set value(String? value) => _$this._value = value;

  TagRuleBuilder() {
    TagRule._defaults(this);
  }

  TagRuleBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _key = $v.key;
      _value = $v.value;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TagRule other) {
    _$v = other as _$TagRule;
  }

  @override
  void update(void Function(TagRuleBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TagRule build() => _build();

  _$TagRule _build() {
    final _$result =
        _$v ??
        _$TagRule._(
          key: BuiltValueNullFieldError.checkNotNull(key, r'TagRule', 'key'),
          value: value,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
