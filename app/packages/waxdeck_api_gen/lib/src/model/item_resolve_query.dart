//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item_resolve_query.g.dart';

/// The item PIDs to resolve.
///
/// Properties:
/// * [pids] - Type-prefixed item PIDs, in the order the answers should come back in. 
@BuiltValue()
abstract class ItemResolveQuery implements Built<ItemResolveQuery, ItemResolveQueryBuilder> {
  /// Type-prefixed item PIDs, in the order the answers should come back in. 
  @BuiltValueField(wireName: r'pids')
  BuiltList<String> get pids;

  ItemResolveQuery._();

  factory ItemResolveQuery([void updates(ItemResolveQueryBuilder b)]) = _$ItemResolveQuery;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ItemResolveQueryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ItemResolveQuery> get serializer => _$ItemResolveQuerySerializer();
}

class _$ItemResolveQuerySerializer implements PrimitiveSerializer<ItemResolveQuery> {
  @override
  final Iterable<Type> types = const [ItemResolveQuery, _$ItemResolveQuery];

  @override
  final String wireName = r'ItemResolveQuery';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ItemResolveQuery object, {
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
    ItemResolveQuery object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ItemResolveQueryBuilder result,
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
  ItemResolveQuery deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ItemResolveQueryBuilder();
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


