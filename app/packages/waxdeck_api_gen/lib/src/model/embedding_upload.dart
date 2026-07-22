//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'embedding_upload.g.dart';

/// One track's embedding.
///
/// Properties:
/// * [pid] - The analyzed track (from the work item).
/// * [essence] - The audio-essence hash (from the work item).
/// * [vector] - The embedding. The server L2-normalizes vectors at ingest, so any consistent scale works. 
@BuiltValue()
abstract class EmbeddingUpload implements Built<EmbeddingUpload, EmbeddingUploadBuilder> {
  /// The analyzed track (from the work item).
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// The audio-essence hash (from the work item).
  @BuiltValueField(wireName: r'essence')
  String get essence;

  /// The embedding. The server L2-normalizes vectors at ingest, so any consistent scale works. 
  @BuiltValueField(wireName: r'vector')
  BuiltList<num> get vector;

  EmbeddingUpload._();

  factory EmbeddingUpload([void updates(EmbeddingUploadBuilder b)]) = _$EmbeddingUpload;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EmbeddingUploadBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EmbeddingUpload> get serializer => _$EmbeddingUploadSerializer();
}

class _$EmbeddingUploadSerializer implements PrimitiveSerializer<EmbeddingUpload> {
  @override
  final Iterable<Type> types = const [EmbeddingUpload, _$EmbeddingUpload];

  @override
  final String wireName = r'EmbeddingUpload';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EmbeddingUpload object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'essence';
    yield serializers.serialize(
      object.essence,
      specifiedType: const FullType(String),
    );
    yield r'vector';
    yield serializers.serialize(
      object.vector,
      specifiedType: const FullType(BuiltList, [FullType(num)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EmbeddingUpload object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EmbeddingUploadBuilder result,
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
        case r'vector':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(num)]),
          ) as BuiltList<num>;
          result.vector.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EmbeddingUpload deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EmbeddingUploadBuilder();
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

