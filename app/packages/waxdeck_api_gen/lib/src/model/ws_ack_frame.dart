//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/playback_session.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_ack_frame.g.dart';

/// Server answer to a successful `cmd` or `register-endpoint` frame, echoing its `id`. Command acks carry the updated session snapshot when the server has one; for commands routed to a playing client (mirror sessions) the snapshot may lag or be absent, because the client's own report is what updates the mirror; controllers render those from the following `session` frame. Registration acks carry the endpoint id. 
///
/// Properties:
/// * [type] - Always `ack`.
/// * [id] - The answered frame's correlation id.
/// * [endpointId] - On registration acks, the endpoint's id.
/// * [session] 
@BuiltValue()
abstract class WsAckFrame implements Built<WsAckFrame, WsAckFrameBuilder> {
  /// Always `ack`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// The answered frame's correlation id.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// On registration acks, the endpoint's id.
  @BuiltValueField(wireName: r'endpointId')
  String? get endpointId;

  @BuiltValueField(wireName: r'session')
  PlaybackSession? get session;

  WsAckFrame._();

  factory WsAckFrame([void updates(WsAckFrameBuilder b)]) = _$WsAckFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsAckFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsAckFrame> get serializer => _$WsAckFrameSerializer();
}

class _$WsAckFrameSerializer implements PrimitiveSerializer<WsAckFrame> {
  @override
  final Iterable<Type> types = const [WsAckFrame, _$WsAckFrame];

  @override
  final String wireName = r'WsAckFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsAckFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    if (object.endpointId != null) {
      yield r'endpointId';
      yield serializers.serialize(
        object.endpointId,
        specifiedType: const FullType(String),
      );
    }
    if (object.session != null) {
      yield r'session';
      yield serializers.serialize(
        object.session,
        specifiedType: const FullType(PlaybackSession),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WsAckFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsAckFrameBuilder result,
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
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'endpointId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.endpointId = valueDes;
          break;
        case r'session':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlaybackSession),
          ) as PlaybackSession;
          result.session.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WsAckFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsAckFrameBuilder();
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

