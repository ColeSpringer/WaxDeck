//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_items_update.g.dart';

/// The full ordered member list, or members to append.
///
/// Properties:
/// * [itemPids] - Item pids in playback order.
/// * [baseUpdatedAt] - Optional lost-update precondition for the replace endpoint: the playlist `updatedAt` this member list was built from, echoed back as read. The comparison is at millisecond granularity, so a client date-time type that cannot hold the server's full precision still matches. A replace against a playlist that changed since then answers `conflict`. Ignored by the append endpoint. 
@BuiltValue()
abstract class PlaylistItemsUpdate implements Built<PlaylistItemsUpdate, PlaylistItemsUpdateBuilder> {
  /// Item pids in playback order.
  @BuiltValueField(wireName: r'itemPids')
  BuiltList<String> get itemPids;

  /// Optional lost-update precondition for the replace endpoint: the playlist `updatedAt` this member list was built from, echoed back as read. The comparison is at millisecond granularity, so a client date-time type that cannot hold the server's full precision still matches. A replace against a playlist that changed since then answers `conflict`. Ignored by the append endpoint. 
  @BuiltValueField(wireName: r'baseUpdatedAt')
  DateTime? get baseUpdatedAt;

  PlaylistItemsUpdate._();

  factory PlaylistItemsUpdate([void updates(PlaylistItemsUpdateBuilder b)]) = _$PlaylistItemsUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistItemsUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistItemsUpdate> get serializer => _$PlaylistItemsUpdateSerializer();
}

class _$PlaylistItemsUpdateSerializer implements PrimitiveSerializer<PlaylistItemsUpdate> {
  @override
  final Iterable<Type> types = const [PlaylistItemsUpdate, _$PlaylistItemsUpdate];

  @override
  final String wireName = r'PlaylistItemsUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistItemsUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'itemPids';
    yield serializers.serialize(
      object.itemPids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.baseUpdatedAt != null) {
      yield r'baseUpdatedAt';
      yield serializers.serialize(
        object.baseUpdatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaylistItemsUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistItemsUpdateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'itemPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.itemPids.replace(valueDes);
          break;
        case r'baseUpdatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.baseUpdatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaylistItemsUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistItemsUpdateBuilder();
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

