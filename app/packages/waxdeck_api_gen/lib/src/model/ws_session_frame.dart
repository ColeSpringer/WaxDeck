//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/playback_session.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_session_frame.g.dart';

/// Server-to-client session state: pushed to the watcher of a session on every change and about once per second while playing, and to a reporting client when its session identity changes or ends. A frame whose session carries `ended` true is terminal for that id. 
///
/// Properties:
/// * [type] - Always `session`.
/// * [session] 
@BuiltValue()
abstract class WsSessionFrame implements Built<WsSessionFrame, WsSessionFrameBuilder> {
  /// Always `session`.
  @BuiltValueField(wireName: r'type')
  String get type;

  @BuiltValueField(wireName: r'session')
  PlaybackSession get session;

  WsSessionFrame._();

  factory WsSessionFrame([void updates(WsSessionFrameBuilder b)]) = _$WsSessionFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsSessionFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsSessionFrame> get serializer => _$WsSessionFrameSerializer();
}

class _$WsSessionFrameSerializer implements PrimitiveSerializer<WsSessionFrame> {
  @override
  final Iterable<Type> types = const [WsSessionFrame, _$WsSessionFrame];

  @override
  final String wireName = r'WsSessionFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsSessionFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    yield r'session';
    yield serializers.serialize(
      object.session,
      specifiedType: const FullType(PlaybackSession),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    WsSessionFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsSessionFrameBuilder result,
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
  WsSessionFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsSessionFrameBuilder();
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

