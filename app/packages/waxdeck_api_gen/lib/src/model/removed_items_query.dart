//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'removed_items_query.g.dart';

/// The items to ask about.
///
/// Properties:
/// * [pids] - Items a device holds downloads of from this server that its latest snapshot did not list. 
@BuiltValue()
abstract class RemovedItemsQuery implements Built<RemovedItemsQuery, RemovedItemsQueryBuilder> {
  /// Items a device holds downloads of from this server that its latest snapshot did not list. 
  @BuiltValueField(wireName: r'pids')
  BuiltList<String> get pids;

  RemovedItemsQuery._();

  factory RemovedItemsQuery([void updates(RemovedItemsQueryBuilder b)]) = _$RemovedItemsQuery;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RemovedItemsQueryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RemovedItemsQuery> get serializer => _$RemovedItemsQuerySerializer();
}

class _$RemovedItemsQuerySerializer implements PrimitiveSerializer<RemovedItemsQuery> {
  @override
  final Iterable<Type> types = const [RemovedItemsQuery, _$RemovedItemsQuery];

  @override
  final String wireName = r'RemovedItemsQuery';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RemovedItemsQuery object, {
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
    RemovedItemsQuery object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RemovedItemsQueryBuilder result,
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
  RemovedItemsQuery deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RemovedItemsQueryBuilder();
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


