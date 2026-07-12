//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item_page.g.dart';

/// One keyset-paginated page of items.
///
/// Properties:
/// * [items] - Items in stable order.
/// * [nextCursor] - Opaque cursor for the next page. Absent on the last page. 
@BuiltValue()
abstract class ItemPage implements Built<ItemPage, ItemPageBuilder> {
  /// Items in stable order.
  @BuiltValueField(wireName: r'items')
  BuiltList<ItemSummary> get items;

  /// Opaque cursor for the next page. Absent on the last page. 
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  ItemPage._();

  factory ItemPage([void updates(ItemPageBuilder b)]) = _$ItemPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ItemPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ItemPage> get serializer => _$ItemPageSerializer();
}

class _$ItemPageSerializer implements PrimitiveSerializer<ItemPage> {
  @override
  final Iterable<Type> types = const [ItemPage, _$ItemPage];

  @override
  final String wireName = r'ItemPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ItemPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(ItemSummary)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ItemPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ItemPageBuilder result,
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
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextCursor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ItemPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ItemPageBuilder();
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

