// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rule_tag_key.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RuleTagKey extends RuleTagKey {
  @override
  final String key;
  @override
  final int itemCount;

  factory _$RuleTagKey([void Function(RuleTagKeyBuilder)? updates]) =>
      (RuleTagKeyBuilder()..update(updates))._build();

  _$RuleTagKey._({required this.key, required this.itemCount}) : super._();
  @override
  RuleTagKey rebuild(void Function(RuleTagKeyBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RuleTagKeyBuilder toBuilder() => RuleTagKeyBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RuleTagKey &&
        key == other.key &&
        itemCount == other.itemCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, key.hashCode);
    _$hash = $jc(_$hash, itemCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RuleTagKey')
          ..add('key', key)
          ..add('itemCount', itemCount))
        .toString();
  }
}

class RuleTagKeyBuilder implements Builder<RuleTagKey, RuleTagKeyBuilder> {
  _$RuleTagKey? _$v;

  String? _key;
  String? get key => _$this._key;
  set key(String? key) => _$this._key = key;

  int? _itemCount;
  int? get itemCount => _$this._itemCount;
  set itemCount(int? itemCount) => _$this._itemCount = itemCount;

  RuleTagKeyBuilder() {
    RuleTagKey._defaults(this);
  }

  RuleTagKeyBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _key = $v.key;
      _itemCount = $v.itemCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RuleTagKey other) {
    _$v = other as _$RuleTagKey;
  }

  @override
  void update(void Function(RuleTagKeyBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RuleTagKey build() => _build();

  _$RuleTagKey _build() {
    final _$result =
        _$v ??
        _$RuleTagKey._(
          key: BuiltValueNullFieldError.checkNotNull(key, r'RuleTagKey', 'key'),
          itemCount: BuiltValueNullFieldError.checkNotNull(
            itemCount,
            r'RuleTagKey',
            'itemCount',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
