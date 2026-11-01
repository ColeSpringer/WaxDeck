//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item_resolution.g.dart';

/// Summaries for the requested PIDs, in request order, minus the ones that could not be resolved. 
///
/// Properties:
/// * [items] 
/// * [departed] - The requested PIDs gone for everyone: no item answers to it any more (a kind change folded it into another) or ever did, or its item lost its files for good (purged from the trash, deleted permanently, or its library removed). As requested, in request order, a repeated PID once, and absent rather than empty when no miss was one of these. 
@BuiltValue()
abstract class ItemResolution implements Built<ItemResolution, ItemResolutionBuilder> {
  @BuiltValueField(wireName: r'items')
  BuiltList<ItemSummary> get items;

  /// The requested PIDs gone for everyone: no item answers to it any more (a kind change folded it into another) or ever did, or its item lost its files for good (purged from the trash, deleted permanently, or its library removed). As requested, in request order, a repeated PID once, and absent rather than empty when no miss was one of these. 
  @BuiltValueField(wireName: r'departed')
  BuiltList<String>? get departed;

  ItemResolution._();

  factory ItemResolution([void updates(ItemResolutionBuilder b)]) = _$ItemResolution;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ItemResolutionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ItemResolution> get serializer => _$ItemResolutionSerializer();
}

class _$ItemResolutionSerializer implements PrimitiveSerializer<ItemResolution> {
  @override
  final Iterable<Type> types = const [ItemResolution, _$ItemResolution];

  @override
  final String wireName = r'ItemResolution';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ItemResolution object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(ItemSummary)]),
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
    ItemResolution object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ItemResolutionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ItemSummary)]),
          ) as BuiltList<ItemSummary>;
          result.items.replace(valueDes);
          break;
        case r'departed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
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
  ItemResolution deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ItemResolutionBuilder();
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


