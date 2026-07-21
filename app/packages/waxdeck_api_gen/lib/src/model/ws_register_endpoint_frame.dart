//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_register_endpoint_frame.g.dart';

/// Client-to-server: declare this connection a controllable player endpoint. Answered with an ack carrying `endpointId`. The endpoint lives while the connection does. 
///
/// Properties:
/// * [type] - Always `register-endpoint`.
/// * [id] - Correlation id for the ack.
/// * [name] - Display name. Defaults to the device session's label. 
/// * [volumeControl] - Whether this client can apply `set-volume`.
/// * [rateControl] - Whether this client can apply `set-rate`.
@BuiltValue()
abstract class WsRegisterEndpointFrame implements Built<WsRegisterEndpointFrame, WsRegisterEndpointFrameBuilder> {
  /// Always `register-endpoint`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// Correlation id for the ack.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// Display name. Defaults to the device session's label. 
  @BuiltValueField(wireName: r'name')
  String? get name;

  /// Whether this client can apply `set-volume`.
  @BuiltValueField(wireName: r'volumeControl')
  bool? get volumeControl;

  /// Whether this client can apply `set-rate`.
  @BuiltValueField(wireName: r'rateControl')
  bool? get rateControl;

  WsRegisterEndpointFrame._();

  factory WsRegisterEndpointFrame([void updates(WsRegisterEndpointFrameBuilder b)]) = _$WsRegisterEndpointFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsRegisterEndpointFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsRegisterEndpointFrame> get serializer => _$WsRegisterEndpointFrameSerializer();
}

class _$WsRegisterEndpointFrameSerializer implements PrimitiveSerializer<WsRegisterEndpointFrame> {
  @override
  final Iterable<Type> types = const [WsRegisterEndpointFrame, _$WsRegisterEndpointFrame];

  @override
  final String wireName = r'WsRegisterEndpointFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsRegisterEndpointFrame object, {
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
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType(String),
      );
    }
    if (object.volumeControl != null) {
      yield r'volumeControl';
      yield serializers.serialize(
        object.volumeControl,
        specifiedType: const FullType(bool),
      );
    }
    if (object.rateControl != null) {
      yield r'rateControl';
      yield serializers.serialize(
        object.rateControl,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WsRegisterEndpointFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsRegisterEndpointFrameBuilder result,
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
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'volumeControl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.volumeControl = valueDes;
          break;
        case r'rateControl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.rateControl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WsRegisterEndpointFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsRegisterEndpointFrameBuilder();
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

