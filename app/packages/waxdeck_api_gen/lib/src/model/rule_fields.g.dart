// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rule_fields.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RuleFields extends RuleFields {
  @override
  final BuiltList<RuleField> fields;
  @override
  final BuiltList<RuleTagKey> tagKeys;

  factory _$RuleFields([void Function(RuleFieldsBuilder)? updates]) =>
      (RuleFieldsBuilder()..update(updates))._build();

  _$RuleFields._({required this.fields, required this.tagKeys}) : super._();
  @override
  RuleFields rebuild(void Function(RuleFieldsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RuleFieldsBuilder toBuilder() => RuleFieldsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RuleFields &&
        fields == other.fields &&
        tagKeys == other.tagKeys;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, fields.hashCode);
    _$hash = $jc(_$hash, tagKeys.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RuleFields')
          ..add('fields', fields)
          ..add('tagKeys', tagKeys))
        .toString();
  }
}

class RuleFieldsBuilder implements Builder<RuleFields, RuleFieldsBuilder> {
  _$RuleFields? _$v;

  ListBuilder<RuleField>? _fields;
  ListBuilder<RuleField> get fields =>
      _$this._fields ??= ListBuilder<RuleField>();
  set fields(ListBuilder<RuleField>? fields) => _$this._fields = fields;

  ListBuilder<RuleTagKey>? _tagKeys;
  ListBuilder<RuleTagKey> get tagKeys =>
      _$this._tagKeys ??= ListBuilder<RuleTagKey>();
  set tagKeys(ListBuilder<RuleTagKey>? tagKeys) => _$this._tagKeys = tagKeys;

  RuleFieldsBuilder() {
    RuleFields._defaults(this);
  }

  RuleFieldsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _fields = $v.fields.toBuilder();
      _tagKeys = $v.tagKeys.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RuleFields other) {
    _$v = other as _$RuleFields;
  }

  @override
  void update(void Function(RuleFieldsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RuleFields build() => _build();

  _$RuleFields _build() {
    _$RuleFields _$result;
    try {
      _$result =
          _$v ??
          _$RuleFields._(fields: fields.build(), tagKeys: tagKeys.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'fields';
        fields.build();
        _$failedField = 'tagKeys';
        tagKeys.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'RuleFields',
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
