//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rejected_embedding.g.dart';

/// One refused embedding.
///
/// Properties:
/// * [pid] - The refused item's pid, when it was parseable.
/// * [essence] - The refused item's essence hash, when it was parseable.
/// * [code] - Stable machine-readable reason (`not-found`, `invalid-request`). 
/// * [message] - Human-readable explanation.
@BuiltValue()
abstract class RejectedEmbedding implements Built<RejectedEmbedding, RejectedEmbeddingBuilder> {
  /// The refused item's pid, when it was parseable.
  @BuiltValueField(wireName: r'pid')
  String? get pid;

  /// The refused item's essence hash, when it was parseable.
  @BuiltValueField(wireName: r'essence')
  String? get essence;

  /// Stable machine-readable reason (`not-found`, `invalid-request`). 
  @BuiltValueField(wireName: r'code')
  String get code;

  /// Human-readable explanation.
  @BuiltValueField(wireName: r'message')
  String get message;

  RejectedEmbedding._();

  factory RejectedEmbedding([void updates(RejectedEmbeddingBuilder b)]) = _$RejectedEmbedding;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RejectedEmbeddingBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RejectedEmbedding> get serializer => _$RejectedEmbeddingSerializer();
}

class _$RejectedEmbeddingSerializer implements PrimitiveSerializer<RejectedEmbedding> {
  @override
  final Iterable<Type> types = const [RejectedEmbedding, _$RejectedEmbedding];

  @override
  final String wireName = r'RejectedEmbedding';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RejectedEmbedding object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.pid != null) {
      yield r'pid';
      yield serializers.serialize(
        object.pid,
        specifiedType: const FullType(String),
      );
    }
    if (object.essence != null) {
      yield r'essence';
      yield serializers.serialize(
        object.essence,
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
  }

  @override
  Object serialize(
    Serializers serializers,
    RejectedEmbedding object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RejectedEmbeddingBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'essence':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.essence = valueDes;
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
  RejectedEmbedding deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RejectedEmbeddingBuilder();
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

