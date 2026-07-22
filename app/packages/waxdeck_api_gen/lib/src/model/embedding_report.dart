//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/embedding_upload.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'embedding_report.g.dart';

/// A batch of computed embeddings.
///
/// Properties:
/// * [model] - Model and version tag the vectors were computed with. Vectors of different models never compare; changing the tag restarts coverage. 
/// * [dims] - Vector dimensionality; every vector's length must match.
/// * [embeddings] 
@BuiltValue()
abstract class EmbeddingReport implements Built<EmbeddingReport, EmbeddingReportBuilder> {
  /// Model and version tag the vectors were computed with. Vectors of different models never compare; changing the tag restarts coverage. 
  @BuiltValueField(wireName: r'model')
  String get model;

  /// Vector dimensionality; every vector's length must match.
  @BuiltValueField(wireName: r'dims')
  int get dims;

  @BuiltValueField(wireName: r'embeddings')
  BuiltList<EmbeddingUpload> get embeddings;

  EmbeddingReport._();

  factory EmbeddingReport([void updates(EmbeddingReportBuilder b)]) = _$EmbeddingReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EmbeddingReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EmbeddingReport> get serializer => _$EmbeddingReportSerializer();
}

class _$EmbeddingReportSerializer implements PrimitiveSerializer<EmbeddingReport> {
  @override
  final Iterable<Type> types = const [EmbeddingReport, _$EmbeddingReport];

  @override
  final String wireName = r'EmbeddingReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EmbeddingReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'model';
    yield serializers.serialize(
      object.model,
      specifiedType: const FullType(String),
    );
    yield r'dims';
    yield serializers.serialize(
      object.dims,
      specifiedType: const FullType(int),
    );
    yield r'embeddings';
    yield serializers.serialize(
      object.embeddings,
      specifiedType: const FullType(BuiltList, [FullType(EmbeddingUpload)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EmbeddingReport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EmbeddingReportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.model = valueDes;
          break;
        case r'dims':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.dims = valueDes;
          break;
        case r'embeddings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EmbeddingUpload)]),
          ) as BuiltList<EmbeddingUpload>;
          result.embeddings.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EmbeddingReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EmbeddingReportBuilder();
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

