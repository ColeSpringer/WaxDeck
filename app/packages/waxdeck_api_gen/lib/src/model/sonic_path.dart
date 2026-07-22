//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'sonic_path.g.dart';

/// A sonic path between two tracks, starting track first, destination last when `complete`. 
///
/// Properties:
/// * [complete] - Whether the path reaches the destination. False when the neighbor graph connects the endpoints only partially; the returned prefix still drifts toward the target. 
/// * [items] 
@BuiltValue()
abstract class SonicPath implements Built<SonicPath, SonicPathBuilder> {
  /// Whether the path reaches the destination. False when the neighbor graph connects the endpoints only partially; the returned prefix still drifts toward the target. 
  @BuiltValueField(wireName: r'complete')
  bool get complete;

  @BuiltValueField(wireName: r'items')
  BuiltList<ItemSummary> get items;

  SonicPath._();

  factory SonicPath([void updates(SonicPathBuilder b)]) = _$SonicPath;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SonicPathBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SonicPath> get serializer => _$SonicPathSerializer();
}

class _$SonicPathSerializer implements PrimitiveSerializer<SonicPath> {
  @override
  final Iterable<Type> types = const [SonicPath, _$SonicPath];

  @override
  final String wireName = r'SonicPath';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SonicPath object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'complete';
    yield serializers.serialize(
      object.complete,
      specifiedType: const FullType(bool),
    );
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(ItemSummary)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SonicPath object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SonicPathBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'complete':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.complete = valueDes;
          break;
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ItemSummary)]),
          ) as BuiltList<ItemSummary>;
          result.items.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SonicPath deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SonicPathBuilder();
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

