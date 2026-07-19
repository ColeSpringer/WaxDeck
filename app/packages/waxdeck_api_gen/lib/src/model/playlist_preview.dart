//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_preview.g.dart';

/// A stateless rule evaluation.
///
/// Properties:
/// * [items] - The first matching items in rule order, honoring the rule's own `limit`. 
/// * [total] - Total items the condition tree matches for the caller, ignoring the rule's `limit`, so editors can render \"matches N items, keeping the first L\". 
@BuiltValue()
abstract class PlaylistPreview implements Built<PlaylistPreview, PlaylistPreviewBuilder> {
  /// The first matching items in rule order, honoring the rule's own `limit`. 
  @BuiltValueField(wireName: r'items')
  BuiltList<ItemSummary> get items;

  /// Total items the condition tree matches for the caller, ignoring the rule's `limit`, so editors can render \"matches N items, keeping the first L\". 
  @BuiltValueField(wireName: r'total')
  int get total;

  PlaylistPreview._();

  factory PlaylistPreview([void updates(PlaylistPreviewBuilder b)]) = _$PlaylistPreview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistPreviewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistPreview> get serializer => _$PlaylistPreviewSerializer();
}

class _$PlaylistPreviewSerializer implements PrimitiveSerializer<PlaylistPreview> {
  @override
  final Iterable<Type> types = const [PlaylistPreview, _$PlaylistPreview];

  @override
  final String wireName = r'PlaylistPreview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(ItemSummary)]),
    );
    yield r'total';
    yield serializers.serialize(
      object.total,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaylistPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistPreviewBuilder result,
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
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.total = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaylistPreview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistPreviewBuilder();
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

