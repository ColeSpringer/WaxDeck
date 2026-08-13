//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_error_frame.g.dart';

/// Server answer to a failed client frame, echoing its `id` when one was readable. `code` draws from the API error vocabulary. A `cmd` refused by the endpoint driving the session carries that endpoint's own code out to whoever sent the command; codes outside the documented vocabulary arrive as `invalid-request` with the refusal's own message. 
///
/// Properties:
/// * [type] - Always `error`.
/// * [id] - The failed frame's correlation id, when known.
/// * [code] - Machine-readable error code.
/// * [message] - Human-readable detail.
/// * [params] - Machine-readable detail keyed per code, the same shape and rules as the REST `Error` schema's `params`: a refusal a client can hit over either transport says the same thing on both. 
@BuiltValue()
abstract class WsErrorFrame implements Built<WsErrorFrame, WsErrorFrameBuilder> {
  /// Always `error`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// The failed frame's correlation id, when known.
  @BuiltValueField(wireName: r'id')
  String? get id;

  /// Machine-readable error code.
  @BuiltValueField(wireName: r'code')
  String get code;

  /// Human-readable detail.
  @BuiltValueField(wireName: r'message')
  String get message;

  /// Machine-readable detail keyed per code, the same shape and rules as the REST `Error` schema's `params`: a refusal a client can hit over either transport says the same thing on both. 
  @BuiltValueField(wireName: r'params')
  BuiltMap<String, String>? get params;

  WsErrorFrame._();

  factory WsErrorFrame([void updates(WsErrorFrameBuilder b)]) = _$WsErrorFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsErrorFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsErrorFrame> get serializer => _$WsErrorFrameSerializer();
}

class _$WsErrorFrameSerializer implements PrimitiveSerializer<WsErrorFrame> {
  @override
  final Iterable<Type> types = const [WsErrorFrame, _$WsErrorFrame];

  @override
  final String wireName = r'WsErrorFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsErrorFrame object, {
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
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
    yield r'message';
    yield serializers.serialize(
      object.message,
      specifiedType: const FullType(String),
    );
    if (object.params != null) {
      yield r'params';
      yield serializers.serialize(
        object.params,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WsErrorFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsErrorFrameBuilder result,
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
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        case r'params':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
          ) as BuiltMap<String, String>;
          result.params.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WsErrorFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsErrorFrameBuilder();
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

