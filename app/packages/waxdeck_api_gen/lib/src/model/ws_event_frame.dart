//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_event_frame.g.dart';

/// One server-to-client frame on the WebSocket event channel (transport in `api/events.md`). An `invalidate` frame tells the client the named topic moved: for `catalog` pull `/sync/catalog` and for `user` pull `/sync/server` from the client's own cursor; for `player` pull `/player/endpoints` and `/player/sessions`, and for `radio` - artwork for an announced title landed - re-read `/radio/stations/{pid}/play-info` for the station being listened to, all of which always return current truth (no cursor); a client tuned to nothing ignores `radio`. Invalidations are coalesced server-side, so one frame can cover many changes, and carry no data, so a redundant pull is harmless. A `resync` frame means continuity was lost for the named stream, or for every stream when `topic` is absent (client queue overflow, pruned history): drop the affected mirror halves, re-mirror through the sync endpoints, then close the socket, reconnect, and resubscribe with the fresh cursors. `resync` never names `player` or `radio` (there is nothing to replay). `type` and `topic` are strings, not closed enums; clients must ignore frames whose `type` they do not recognize. 
///
/// Properties:
/// * [type] - Frame discriminator: `invalidate` or `resync`.
/// * [topic] - Which topic the frame is about (`catalog`, `user`, `player`, or `radio`). Always present on `invalidate`; on `resync` its absence means every stream. 
@BuiltValue()
abstract class WsEventFrame implements Built<WsEventFrame, WsEventFrameBuilder> {
  /// Frame discriminator: `invalidate` or `resync`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// Which topic the frame is about (`catalog`, `user`, `player`, or `radio`). Always present on `invalidate`; on `resync` its absence means every stream. 
  @BuiltValueField(wireName: r'topic')
  String? get topic;

  WsEventFrame._();

  factory WsEventFrame([void updates(WsEventFrameBuilder b)]) = _$WsEventFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsEventFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsEventFrame> get serializer => _$WsEventFrameSerializer();
}

class _$WsEventFrameSerializer implements PrimitiveSerializer<WsEventFrame> {
  @override
  final Iterable<Type> types = const [WsEventFrame, _$WsEventFrame];

  @override
  final String wireName = r'WsEventFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsEventFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    if (object.topic != null) {
      yield r'topic';
      yield serializers.serialize(
        object.topic,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WsEventFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsEventFrameBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.type = valueDes;
          break;
        case r'topic':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.topic = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WsEventFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsEventFrameBuilder();
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

