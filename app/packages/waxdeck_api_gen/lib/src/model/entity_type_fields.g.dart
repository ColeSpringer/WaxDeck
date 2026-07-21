// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_type_fields.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EntityTypeFields extends EntityTypeFields {
  @override
  final String entityType;
  @override
  final BuiltList<EditableField> fields;

  factory _$EntityTypeFields([
    void Function(EntityTypeFieldsBuilder)? updates,
  ]) => (EntityTypeFieldsBuilder()..update(updates))._build();

  _$EntityTypeFields._({required this.entityType, required this.fields})
    : super._();
  @override
  EntityTypeFields rebuild(void Function(EntityTypeFieldsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EntityTypeFieldsBuilder toBuilder() =>
      EntityTypeFieldsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EntityTypeFields &&
        entityType == other.entityType &&
        fields == other.fields;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entityType.hashCode);
    _$hash = $jc(_$hash, fields.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EntityTypeFields')
          ..add('entityType', entityType)
          ..add('fields', fields))
        .toString();
  }
}

class EntityTypeFieldsBuilder
    implements Builder<EntityTypeFields, EntityTypeFieldsBuilder> {
  _$EntityTypeFields? _$v;

  String? _entityType;
  String? get entityType => _$this._entityType;
  set entityType(String? entityType) => _$this._entityType = entityType;

  ListBuilder<EditableField>? _fields;
  ListBuilder<EditableField> get fields =>
      _$this._fields ??= ListBuilder<EditableField>();
  set fields(ListBuilder<EditableField>? fields) => _$this._fields = fields;

  EntityTypeFieldsBuilder() {
    EntityTypeFields._defaults(this);
  }

  EntityTypeFieldsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entityType = $v.entityType;
      _fields = $v.fields.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EntityTypeFields other) {
    _$v = other as _$EntityTypeFields;
  }

  @override
  void update(void Function(EntityTypeFieldsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EntityTypeFields build() => _build();

  _$EntityTypeFields _build() {
    _$EntityTypeFields _$result;
    try {
      _$result =
          _$v ??
          _$EntityTypeFields._(
            entityType: BuiltValueNullFieldError.checkNotNull(
              entityType,
              r'EntityTypeFields',
              'entityType',
            ),
            fields: fields.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'fields';
        fields.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EntityTypeFields',
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
