//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/editable_field.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'entity_type_fields.g.dart';

/// One entity type's editable vocabulary.
///
/// Properties:
/// * [entityType] - `album`, `artist`, or `release-group`.
/// * [fields] - Editable entity fields.
@BuiltValue()
abstract class EntityTypeFields implements Built<EntityTypeFields, EntityTypeFieldsBuilder> {
  /// `album`, `artist`, or `release-group`.
  @BuiltValueField(wireName: r'entityType')
  String get entityType;

  /// Editable entity fields.
  @BuiltValueField(wireName: r'fields')
  BuiltList<EditableField> get fields;

  EntityTypeFields._();

  factory EntityTypeFields([void updates(EntityTypeFieldsBuilder b)]) = _$EntityTypeFields;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EntityTypeFieldsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EntityTypeFields> get serializer => _$EntityTypeFieldsSerializer();
}

class _$EntityTypeFieldsSerializer implements PrimitiveSerializer<EntityTypeFields> {
  @override
  final Iterable<Type> types = const [EntityTypeFields, _$EntityTypeFields];

  @override
  final String wireName = r'EntityTypeFields';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EntityTypeFields object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entityType';
    yield serializers.serialize(
      object.entityType,
      specifiedType: const FullType(String),
    );
    yield r'fields';
    yield serializers.serialize(
      object.fields,
      specifiedType: const FullType(BuiltList, [FullType(EditableField)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EntityTypeFields object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EntityTypeFieldsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entityType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.entityType = valueDes;
          break;
        case r'fields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EditableField)]),
          ) as BuiltList<EditableField>;
          result.fields.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EntityTypeFields deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EntityTypeFieldsBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

