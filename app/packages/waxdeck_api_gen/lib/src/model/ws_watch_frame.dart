//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_watch_frame.g.dart';

/// Client-to-server: follow one session's live state. Watching follows session visibility (your own sessions, others' on shared endpoints). A new watch replaces the previous one; omitting `sessionId` stops watching. A successful watch is not acked (the current state arrives immediately as a `session` frame); a watch of an unknown or invisible session answers an `error` frame with `not-found`, echoing `id` when sent. 
///
/// Properties:
/// * [type] - Always `watch`.
/// * [id] - Optional correlation id, echoed on a failure.
/// * [sessionId] - The session to follow.
@BuiltValue()
abstract class WsWatchFrame implements Built<WsWatchFrame, WsWatchFrameBuilder> {
  /// Always `watch`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// Optional correlation id, echoed on a failure.
  @BuiltValueField(wireName: r'id')
  String? get id;

  /// The session to follow.
  @BuiltValueField(wireName: r'sessionId')
  String? get sessionId;

  WsWatchFrame._();

  factory WsWatchFrame([void updates(WsWatchFrameBuilder b)]) = _$WsWatchFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsWatchFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsWatchFrame> get serializer => _$WsWatchFrameSerializer();
}

class _$WsWatchFrameSerializer implements PrimitiveSerializer<WsWatchFrame> {
  @override
  final Iterable<Type> types = const [WsWatchFrame, _$WsWatchFrame];

  @override
  final String wireName = r'WsWatchFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsWatchFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.sessionId != null) {
      yield r'sessionId';
      yield serializers.serialize(
        object.sessionId,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WsWatchFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsWatchFrameBuilder result,
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
        case r'sessionId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sessionId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WsWatchFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsWatchFrameBuilder();
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

