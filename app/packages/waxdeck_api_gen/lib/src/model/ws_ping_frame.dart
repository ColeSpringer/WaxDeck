//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_ping_frame.g.dart';

/// Client-to-server clock probe for NTP-style offset estimation (unrelated to WebSocket protocol pings). 
///
/// Properties:
/// * [type] - Always `ping`.
/// * [t] - Opaque client timestamp, echoed back verbatim.
@BuiltValue()
abstract class WsPingFrame implements Built<WsPingFrame, WsPingFrameBuilder> {
  /// Always `ping`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// Opaque client timestamp, echoed back verbatim.
  @BuiltValueField(wireName: r't')
  int get t;

  WsPingFrame._();

  factory WsPingFrame([void updates(WsPingFrameBuilder b)]) = _$WsPingFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsPingFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsPingFrame> get serializer => _$WsPingFrameSerializer();
}

class _$WsPingFrameSerializer implements PrimitiveSerializer<WsPingFrame> {
  @override
  final Iterable<Type> types = const [WsPingFrame, _$WsPingFrame];

  @override
  final String wireName = r'WsPingFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsPingFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    yield r't';
    yield serializers.serialize(
      object.t,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    WsPingFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsPingFrameBuilder result,
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
        case r't':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.t = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WsPingFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsPingFrameBuilder();
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

