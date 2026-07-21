//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_command_result_frame.g.dart';

/// Client-to-server answer to an `endpoint-cmd`, echoing its `id`. Sent exactly once per routed command. 
///
/// Properties:
/// * [type] - Always `cmd-result`.
/// * [id] - The routed command's correlation id.
/// * [ok] - Whether the command was applied.
/// * [code] - Machine-readable failure code when `ok` is false.
/// * [message] - Human-readable failure detail when `ok` is false.
@BuiltValue()
abstract class WsCommandResultFrame implements Built<WsCommandResultFrame, WsCommandResultFrameBuilder> {
  /// Always `cmd-result`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// The routed command's correlation id.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// Whether the command was applied.
  @BuiltValueField(wireName: r'ok')
  bool get ok;

  /// Machine-readable failure code when `ok` is false.
  @BuiltValueField(wireName: r'code')
  String? get code;

  /// Human-readable failure detail when `ok` is false.
  @BuiltValueField(wireName: r'message')
  String? get message;

  WsCommandResultFrame._();

  factory WsCommandResultFrame([void updates(WsCommandResultFrameBuilder b)]) = _$WsCommandResultFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsCommandResultFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsCommandResultFrame> get serializer => _$WsCommandResultFrameSerializer();
}

class _$WsCommandResultFrameSerializer implements PrimitiveSerializer<WsCommandResultFrame> {
  @override
  final Iterable<Type> types = const [WsCommandResultFrame, _$WsCommandResultFrame];

  @override
  final String wireName = r'WsCommandResultFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsCommandResultFrame object, {
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
    yield r'ok';
    yield serializers.serialize(
      object.ok,
      specifiedType: const FullType(bool),
    );
    if (object.code != null) {
      yield r'code';
      yield serializers.serialize(
        object.code,
        specifiedType: const FullType(String),
      );
    }
    if (object.message != null) {
      yield r'message';
      yield serializers.serialize(
        object.message,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WsCommandResultFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsCommandResultFrameBuilder result,
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
        case r'ok':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.ok = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WsCommandResultFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsCommandResultFrameBuilder();
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

