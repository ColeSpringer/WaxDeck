//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rejected_listen.g.dart';

/// One session the server refused, and why.
///
/// Properties:
/// * [sessionId] - The refused session's idempotency ID.
/// * [code] - Stable machine-readable reason (`not-found`, `invalid-request`).
/// * [message] - Human-readable explanation.
@BuiltValue()
abstract class RejectedListen implements Built<RejectedListen, RejectedListenBuilder> {
  /// The refused session's idempotency ID.
  @BuiltValueField(wireName: r'sessionId')
  String get sessionId;

  /// Stable machine-readable reason (`not-found`, `invalid-request`).
  @BuiltValueField(wireName: r'code')
  String get code;

  /// Human-readable explanation.
  @BuiltValueField(wireName: r'message')
  String get message;

  RejectedListen._();

  factory RejectedListen([void updates(RejectedListenBuilder b)]) = _$RejectedListen;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RejectedListenBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RejectedListen> get serializer => _$RejectedListenSerializer();
}

class _$RejectedListenSerializer implements PrimitiveSerializer<RejectedListen> {
  @override
  final Iterable<Type> types = const [RejectedListen, _$RejectedListen];

  @override
  final String wireName = r'RejectedListen';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RejectedListen object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sessionId';
    yield serializers.serialize(
      object.sessionId,
      specifiedType: const FullType(String),
    );
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
  }

  @override
  Object serialize(
    Serializers serializers,
    RejectedListen object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RejectedListenBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sessionId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sessionId = valueDes;
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
  RejectedListen deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RejectedListenBuilder();
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

