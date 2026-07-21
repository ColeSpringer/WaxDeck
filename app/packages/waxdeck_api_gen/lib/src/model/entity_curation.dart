//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/entity_curated_field.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'entity_curation.g.dart';

/// An entity's curated fields.
///
/// Properties:
/// * [curated] - Curated fields with provenance.
@BuiltValue()
abstract class EntityCuration implements Built<EntityCuration, EntityCurationBuilder> {
  /// Curated fields with provenance.
  @BuiltValueField(wireName: r'curated')
  BuiltList<EntityCuratedField> get curated;

  EntityCuration._();

  factory EntityCuration([void updates(EntityCurationBuilder b)]) = _$EntityCuration;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EntityCurationBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EntityCuration> get serializer => _$EntityCurationSerializer();
}

class _$EntityCurationSerializer implements PrimitiveSerializer<EntityCuration> {
  @override
  final Iterable<Type> types = const [EntityCuration, _$EntityCuration];

  @override
  final String wireName = r'EntityCuration';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EntityCuration object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'curated';
    yield serializers.serialize(
      object.curated,
      specifiedType: const FullType(BuiltList, [FullType(EntityCuratedField)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EntityCuration object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EntityCurationBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'curated':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EntityCuratedField)]),
          ) as BuiltList<EntityCuratedField>;
          result.curated.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EntityCuration deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EntityCurationBuilder();
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

