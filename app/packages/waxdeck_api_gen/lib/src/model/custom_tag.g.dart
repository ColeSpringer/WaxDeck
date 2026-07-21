// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_tag.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CustomTag extends CustomTag {
  @override
  final String key;
  @override
  final BuiltList<String> values;

  factory _$CustomTag([void Function(CustomTagBuilder)? updates]) =>
      (CustomTagBuilder()..update(updates))._build();

  _$CustomTag._({required this.key, required this.values}) : super._();
  @override
  CustomTag rebuild(void Function(CustomTagBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CustomTagBuilder toBuilder() => CustomTagBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CustomTag && key == other.key && values == other.values;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, key.hashCode);
    _$hash = $jc(_$hash, values.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CustomTag')
          ..add('key', key)
          ..add('values', values))
        .toString();
  }
}

class CustomTagBuilder implements Builder<CustomTag, CustomTagBuilder> {
  _$CustomTag? _$v;

  String? _key;
  String? get key => _$this._key;
  set key(String? key) => _$this._key = key;

  ListBuilder<String>? _values;
  ListBuilder<String> get values => _$this._values ??= ListBuilder<String>();
  set values(ListBuilder<String>? values) => _$this._values = values;

  CustomTagBuilder() {
    CustomTag._defaults(this);
  }

  CustomTagBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _key = $v.key;
      _values = $v.values.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CustomTag other) {
    _$v = other as _$CustomTag;
  }

  @override
  void update(void Function(CustomTagBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CustomTag build() => _build();

  _$CustomTag _build() {
    _$CustomTag _$result;
    try {
      _$result =
          _$v ??
          _$CustomTag._(
            key: BuiltValueNullFieldError.checkNotNull(
              key,
              r'CustomTag',
              'key',
            ),
            values: values.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'values';
        values.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CustomTag',
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
