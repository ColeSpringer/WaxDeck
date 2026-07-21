//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'entity_curated_field.g.dart';

/// One curated entity field.
///
/// Properties:
/// * [field] - The field.
/// * [value] - The curated value.
/// * [source_] - The producer, as in item provenance.
/// * [locked] - Whether the field is locked.
/// * [updatedAt] - When the value last changed.
@BuiltValue()
abstract class EntityCuratedField implements Built<EntityCuratedField, EntityCuratedFieldBuilder> {
  /// The field.
  @BuiltValueField(wireName: r'field')
  String get field;

  /// The curated value.
  @BuiltValueField(wireName: r'value')
  String? get value;

  /// The producer, as in item provenance.
  @BuiltValueField(wireName: r'source')
  String get source_;

  /// Whether the field is locked.
  @BuiltValueField(wireName: r'locked')
  bool get locked;

  /// When the value last changed.
  @BuiltValueField(wireName: r'updatedAt')
  DateTime? get updatedAt;

  EntityCuratedField._();

  factory EntityCuratedField([void updates(EntityCuratedFieldBuilder b)]) = _$EntityCuratedField;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EntityCuratedFieldBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EntityCuratedField> get serializer => _$EntityCuratedFieldSerializer();
}

class _$EntityCuratedFieldSerializer implements PrimitiveSerializer<EntityCuratedField> {
  @override
  final Iterable<Type> types = const [EntityCuratedField, _$EntityCuratedField];

  @override
  final String wireName = r'EntityCuratedField';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EntityCuratedField object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'field';
    yield serializers.serialize(
      object.field,
      specifiedType: const FullType(String),
    );
    if (object.value != null) {
      yield r'value';
      yield serializers.serialize(
        object.value,
        specifiedType: const FullType(String),
      );
    }
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(String),
    );
    yield r'locked';
    yield serializers.serialize(
      object.locked,
      specifiedType: const FullType(bool),
    );
    if (object.updatedAt != null) {
      yield r'updatedAt';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EntityCuratedField object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EntityCuratedFieldBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'field':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.field = valueDes;
          break;
        case r'value':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.value = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.source_ = valueDes;
          break;
        case r'locked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.locked = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EntityCuratedField deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EntityCuratedFieldBuilder();
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

