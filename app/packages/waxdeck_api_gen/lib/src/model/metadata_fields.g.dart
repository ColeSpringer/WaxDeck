// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata_fields.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MetadataFields extends MetadataFields {
  @override
  final BuiltList<KindFields> kinds;
  @override
  final BuiltList<EntityTypeFields> entityTypes;

  factory _$MetadataFields([void Function(MetadataFieldsBuilder)? updates]) =>
      (MetadataFieldsBuilder()..update(updates))._build();

  _$MetadataFields._({required this.kinds, required this.entityTypes})
    : super._();
  @override
  MetadataFields rebuild(void Function(MetadataFieldsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MetadataFieldsBuilder toBuilder() => MetadataFieldsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MetadataFields &&
        kinds == other.kinds &&
        entityTypes == other.entityTypes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kinds.hashCode);
    _$hash = $jc(_$hash, entityTypes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MetadataFields')
          ..add('kinds', kinds)
          ..add('entityTypes', entityTypes))
        .toString();
  }
}

class MetadataFieldsBuilder
    implements Builder<MetadataFields, MetadataFieldsBuilder> {
  _$MetadataFields? _$v;

  ListBuilder<KindFields>? _kinds;
  ListBuilder<KindFields> get kinds =>
      _$this._kinds ??= ListBuilder<KindFields>();
  set kinds(ListBuilder<KindFields>? kinds) => _$this._kinds = kinds;

  ListBuilder<EntityTypeFields>? _entityTypes;
  ListBuilder<EntityTypeFields> get entityTypes =>
      _$this._entityTypes ??= ListBuilder<EntityTypeFields>();
  set entityTypes(ListBuilder<EntityTypeFields>? entityTypes) =>
      _$this._entityTypes = entityTypes;

  MetadataFieldsBuilder() {
    MetadataFields._defaults(this);
  }

  MetadataFieldsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kinds = $v.kinds.toBuilder();
      _entityTypes = $v.entityTypes.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MetadataFields other) {
    _$v = other as _$MetadataFields;
  }

  @override
  void update(void Function(MetadataFieldsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MetadataFields build() => _build();

  _$MetadataFields _build() {
    _$MetadataFields _$result;
    try {
      _$result =
          _$v ??
          _$MetadataFields._(
            kinds: kinds.build(),
            entityTypes: entityTypes.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'kinds';
        kinds.build();
        _$failedField = 'entityTypes';
        entityTypes.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'MetadataFields',
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
