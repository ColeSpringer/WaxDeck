//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/entity_card.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'entity_card_list.g.dart';

/// Cards for the requested PIDs, in request order, minus the ones that could not be resolved. 
///
/// Properties:
/// * [entities] 
/// * [departed] - The requested PIDs that no longer name anything on this server, for anyone: deleted, merged away, or never real. In request order, a repeated PID once, and absent rather than empty when every miss was merely out of the caller's sight (a grant, a lapsed subscription, the trash) - those stay unnamed, because they can come back. This is the set a client holding `Prefs.pinned` prunes. 
@BuiltValue()
abstract class EntityCardList implements Built<EntityCardList, EntityCardListBuilder> {
  @BuiltValueField(wireName: r'entities')
  BuiltList<EntityCard> get entities;

  /// The requested PIDs that no longer name anything on this server, for anyone: deleted, merged away, or never real. In request order, a repeated PID once, and absent rather than empty when every miss was merely out of the caller's sight (a grant, a lapsed subscription, the trash) - those stay unnamed, because they can come back. This is the set a client holding `Prefs.pinned` prunes. 
  @BuiltValueField(wireName: r'departed')
  BuiltList<String>? get departed;

  EntityCardList._();

  factory EntityCardList([void updates(EntityCardListBuilder b)]) = _$EntityCardList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EntityCardListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EntityCardList> get serializer => _$EntityCardListSerializer();
}

class _$EntityCardListSerializer implements PrimitiveSerializer<EntityCardList> {
  @override
  final Iterable<Type> types = const [EntityCardList, _$EntityCardList];

  @override
  final String wireName = r'EntityCardList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EntityCardList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entities';
    yield serializers.serialize(
      object.entities,
      specifiedType: const FullType(BuiltList, [FullType(EntityCard)]),
    );
    if (object.departed != null) {
      yield r'departed';
      yield serializers.serialize(
        object.departed,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EntityCardList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EntityCardListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entities':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EntityCard)]),
          ) as BuiltList<EntityCard>;
          result.entities.replace(valueDes);
          break;
        case r'departed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.departed.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EntityCardList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EntityCardListBuilder();
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

