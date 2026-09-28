//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'similarity_work_item.g.dart';

/// One track awaiting embedding.
///
/// Properties:
/// * [pid] - The track to analyze.
/// * [essence] - The analysis key: the audio essence, windowed for a cue-carved track. Opaque to workers; echo it back with the vector. 
/// * [audioUrl] - Origin-relative URL serving decode-ready audio (16 kHz mono, gain untouched). Append `format=flac` for lossless at roughly half the bytes (remote workers); the default is WAV. Authenticate with the same worker token. 
/// * [localPath] - The source file's library-relative path, for a same-host worker (`WAXDECK_WORKER_LOCAL_PATHS`) that mounts the library read-only; never for a cue-carved track, whose file is the whole rip. 
/// * [durationMs] - Track duration in milliseconds.
/// * [mediaType] 
@BuiltValue()
abstract class SimilarityWorkItem implements Built<SimilarityWorkItem, SimilarityWorkItemBuilder> {
  /// The track to analyze.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// The analysis key: the audio essence, windowed for a cue-carved track. Opaque to workers; echo it back with the vector. 
  @BuiltValueField(wireName: r'essence')
  String get essence;

  /// Origin-relative URL serving decode-ready audio (16 kHz mono, gain untouched). Append `format=flac` for lossless at roughly half the bytes (remote workers); the default is WAV. Authenticate with the same worker token. 
  @BuiltValueField(wireName: r'audioUrl')
  String get audioUrl;

  /// The source file's library-relative path, for a same-host worker (`WAXDECK_WORKER_LOCAL_PATHS`) that mounts the library read-only; never for a cue-carved track, whose file is the whole rip. 
  @BuiltValueField(wireName: r'localPath')
  String? get localPath;

  /// Track duration in milliseconds.
  @BuiltValueField(wireName: r'durationMs')
  int get durationMs;

  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  SimilarityWorkItem._();

  factory SimilarityWorkItem([void updates(SimilarityWorkItemBuilder b)]) = _$SimilarityWorkItem;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SimilarityWorkItemBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SimilarityWorkItem> get serializer => _$SimilarityWorkItemSerializer();
}

class _$SimilarityWorkItemSerializer implements PrimitiveSerializer<SimilarityWorkItem> {
  @override
  final Iterable<Type> types = const [SimilarityWorkItem, _$SimilarityWorkItem];

  @override
  final String wireName = r'SimilarityWorkItem';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SimilarityWorkItem object, {
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
    yield r'audioUrl';
    yield serializers.serialize(
      object.audioUrl,
      specifiedType: const FullType(String),
    );
    if (object.localPath != null) {
      yield r'localPath';
      yield serializers.serialize(
        object.localPath,
        specifiedType: const FullType(String),
      );
    }
    yield r'durationMs';
    yield serializers.serialize(
      object.durationMs,
      specifiedType: const FullType(int),
    );
    yield r'mediaType';
    yield serializers.serialize(
      object.mediaType,
      specifiedType: const FullType(MediaType),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SimilarityWorkItem object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SimilarityWorkItemBuilder result,
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
        case r'audioUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.audioUrl = valueDes;
          break;
        case r'localPath':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.localPath = valueDes;
          break;
        case r'durationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMs = valueDes;
          break;
        case r'mediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaType),
          ) as MediaType;
          result.mediaType = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SimilarityWorkItem deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SimilarityWorkItemBuilder();
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


