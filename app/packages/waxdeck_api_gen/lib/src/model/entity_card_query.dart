//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'entity_card_query.g.dart';

/// The entity PIDs to resolve.
///
/// Properties:
/// * [pids] - Type-prefixed entity PIDs, in the order the answers should come back in. Duplicates answer once per occurrence.  The response preserves this order but not these positions: a PID that cannot be resolved is omitted, so the two lists line up only when everything resolved. Match a card to its handle by `pid`, never by index. 
@BuiltValue()
abstract class EntityCardQuery implements Built<EntityCardQuery, EntityCardQueryBuilder> {
  /// Type-prefixed entity PIDs, in the order the answers should come back in. Duplicates answer once per occurrence.  The response preserves this order but not these positions: a PID that cannot be resolved is omitted, so the two lists line up only when everything resolved. Match a card to its handle by `pid`, never by index. 
  @BuiltValueField(wireName: r'pids')
  BuiltList<String> get pids;

  EntityCardQuery._();

  factory EntityCardQuery([void updates(EntityCardQueryBuilder b)]) = _$EntityCardQuery;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EntityCardQueryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EntityCardQuery> get serializer => _$EntityCardQuerySerializer();
}

class _$EntityCardQuerySerializer implements PrimitiveSerializer<EntityCardQuery> {
  @override
  final Iterable<Type> types = const [EntityCardQuery, _$EntityCardQuery];

  @override
  final String wireName = r'EntityCardQuery';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EntityCardQuery object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pids';
    yield serializers.serialize(
      object.pids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EntityCardQuery object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EntityCardQueryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.pids.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EntityCardQuery deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EntityCardQueryBuilder();
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

