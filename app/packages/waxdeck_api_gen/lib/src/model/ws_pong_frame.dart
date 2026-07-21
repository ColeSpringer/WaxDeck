//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_pong_frame.g.dart';

/// Server answer to a `ping` frame.
///
/// Properties:
/// * [type] - Always `pong`.
/// * [t] - The ping's `t`, echoed verbatim.
/// * [at] - Server clock in Unix milliseconds at handling time.
@BuiltValue()
abstract class WsPongFrame implements Built<WsPongFrame, WsPongFrameBuilder> {
  /// Always `pong`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// The ping's `t`, echoed verbatim.
  @BuiltValueField(wireName: r't')
  int get t;

  /// Server clock in Unix milliseconds at handling time.
  @BuiltValueField(wireName: r'at')
  int get at;

  WsPongFrame._();

  factory WsPongFrame([void updates(WsPongFrameBuilder b)]) = _$WsPongFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsPongFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsPongFrame> get serializer => _$WsPongFrameSerializer();
}

class _$WsPongFrameSerializer implements PrimitiveSerializer<WsPongFrame> {
  @override
  final Iterable<Type> types = const [WsPongFrame, _$WsPongFrame];

  @override
  final String wireName = r'WsPongFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsPongFrame object, {
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
    yield r'at';
    yield serializers.serialize(
      object.at,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    WsPongFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsPongFrameBuilder result,
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
        case r'at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.at = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WsPongFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsPongFrameBuilder();
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

