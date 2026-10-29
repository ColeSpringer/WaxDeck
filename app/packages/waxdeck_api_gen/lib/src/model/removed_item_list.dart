//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'removed_item_list.g.dart';

/// The asked-about items that are gone for good.
///
/// Properties:
/// * [pids] - The requested PIDs the server can never put back, as asked. An item not named here may still return. 
@BuiltValue()
abstract class RemovedItemList implements Built<RemovedItemList, RemovedItemListBuilder> {
  /// The requested PIDs the server can never put back, as asked. An item not named here may still return. 
  @BuiltValueField(wireName: r'pids')
  BuiltList<String> get pids;

  RemovedItemList._();

  factory RemovedItemList([void updates(RemovedItemListBuilder b)]) = _$RemovedItemList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RemovedItemListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RemovedItemList> get serializer => _$RemovedItemListSerializer();
}

class _$RemovedItemListSerializer implements PrimitiveSerializer<RemovedItemList> {
  @override
  final Iterable<Type> types = const [RemovedItemList, _$RemovedItemList];

  @override
  final String wireName = r'RemovedItemList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RemovedItemList object, {
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
    RemovedItemList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RemovedItemListBuilder result,
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
  RemovedItemList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RemovedItemListBuilder();
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


