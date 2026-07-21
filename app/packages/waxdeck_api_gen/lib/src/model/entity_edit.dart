//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'entity_edit.g.dart';

/// Entity field edits.
///
/// Properties:
/// * [edits] - Field name to new value, from the entity type's vocabulary; empty clears. 
/// * [writeBack] - Push tag-formed values into member files.
/// * [lock] - Lock the edited entity fields.
/// * [force] - Override existing locks.
@BuiltValue()
abstract class EntityEdit implements Built<EntityEdit, EntityEditBuilder> {
  /// Field name to new value, from the entity type's vocabulary; empty clears. 
  @BuiltValueField(wireName: r'edits')
  BuiltMap<String, String> get edits;

  /// Push tag-formed values into member files.
  @BuiltValueField(wireName: r'writeBack')
  bool? get writeBack;

  /// Lock the edited entity fields.
  @BuiltValueField(wireName: r'lock')
  bool? get lock;

  /// Override existing locks.
  @BuiltValueField(wireName: r'force')
  bool? get force;

  EntityEdit._();

  factory EntityEdit([void updates(EntityEditBuilder b)]) = _$EntityEdit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EntityEditBuilder b) => b
      ..writeBack = false
      ..lock = true
      ..force = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<EntityEdit> get serializer => _$EntityEditSerializer();
}

class _$EntityEditSerializer implements PrimitiveSerializer<EntityEdit> {
  @override
  final Iterable<Type> types = const [EntityEdit, _$EntityEdit];

  @override
  final String wireName = r'EntityEdit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EntityEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'edits';
    yield serializers.serialize(
      object.edits,
      specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
    );
    if (object.writeBack != null) {
      yield r'writeBack';
      yield serializers.serialize(
        object.writeBack,
        specifiedType: const FullType(bool),
      );
    }
    if (object.lock != null) {
      yield r'lock';
      yield serializers.serialize(
        object.lock,
        specifiedType: const FullType(bool),
      );
    }
    if (object.force != null) {
      yield r'force';
      yield serializers.serialize(
        object.force,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EntityEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EntityEditBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'edits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
          ) as BuiltMap<String, String>;
          result.edits.replace(valueDes);
          break;
        case r'writeBack':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.writeBack = valueDes;
          break;
        case r'lock':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.lock = valueDes;
          break;
        case r'force':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.force = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EntityEdit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EntityEditBuilder();
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

