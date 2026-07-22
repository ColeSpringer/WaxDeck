//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/rejected_embedding.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'embedding_ingest_result.g.dart';

/// Outcome of an embedding ingest batch.
///
/// Properties:
/// * [accepted] - Vectors stored for the first time.
/// * [replaced] - Vectors that overwrote a stored one (re-analysis).
/// * [rejected] - Vectors the server refused, and why.
@BuiltValue()
abstract class EmbeddingIngestResult implements Built<EmbeddingIngestResult, EmbeddingIngestResultBuilder> {
  /// Vectors stored for the first time.
  @BuiltValueField(wireName: r'accepted')
  int get accepted;

  /// Vectors that overwrote a stored one (re-analysis).
  @BuiltValueField(wireName: r'replaced')
  int get replaced;

  /// Vectors the server refused, and why.
  @BuiltValueField(wireName: r'rejected')
  BuiltList<RejectedEmbedding>? get rejected;

  EmbeddingIngestResult._();

  factory EmbeddingIngestResult([void updates(EmbeddingIngestResultBuilder b)]) = _$EmbeddingIngestResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EmbeddingIngestResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EmbeddingIngestResult> get serializer => _$EmbeddingIngestResultSerializer();
}

class _$EmbeddingIngestResultSerializer implements PrimitiveSerializer<EmbeddingIngestResult> {
  @override
  final Iterable<Type> types = const [EmbeddingIngestResult, _$EmbeddingIngestResult];

  @override
  final String wireName = r'EmbeddingIngestResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EmbeddingIngestResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'accepted';
    yield serializers.serialize(
      object.accepted,
      specifiedType: const FullType(int),
    );
    yield r'replaced';
    yield serializers.serialize(
      object.replaced,
      specifiedType: const FullType(int),
    );
    if (object.rejected != null) {
      yield r'rejected';
      yield serializers.serialize(
        object.rejected,
        specifiedType: const FullType(BuiltList, [FullType(RejectedEmbedding)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EmbeddingIngestResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EmbeddingIngestResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'accepted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.accepted = valueDes;
          break;
        case r'replaced':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.replaced = valueDes;
          break;
        case r'rejected':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RejectedEmbedding)]),
          ) as BuiltList<RejectedEmbedding>;
          result.rejected.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EmbeddingIngestResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EmbeddingIngestResultBuilder();
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

