//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_create.g.dart';

/// A new upload session.
///
/// Properties:
/// * [fileName] - The file's name (base name only; any path is rejected). The extension picks the accepted-format check. 
/// * [sizeBytes] - Total file size in bytes.
/// * [mediaType] 
/// * [libraryPid] - Target library; required when several libraries of the media type are visible to the caller. 
/// * [sha256] - Lowercase hex SHA-256 of the file, for the up-front exact duplicate warning and the completion integrity check. 
@BuiltValue()
abstract class UploadCreate implements Built<UploadCreate, UploadCreateBuilder> {
  /// The file's name (base name only; any path is rejected). The extension picks the accepted-format check. 
  @BuiltValueField(wireName: r'fileName')
  String get fileName;

  /// Total file size in bytes.
  @BuiltValueField(wireName: r'sizeBytes')
  int get sizeBytes;

  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  /// Target library; required when several libraries of the media type are visible to the caller. 
  @BuiltValueField(wireName: r'libraryPid')
  String? get libraryPid;

  /// Lowercase hex SHA-256 of the file, for the up-front exact duplicate warning and the completion integrity check. 
  @BuiltValueField(wireName: r'sha256')
  String? get sha256;

  UploadCreate._();

  factory UploadCreate([void updates(UploadCreateBuilder b)]) = _$UploadCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadCreateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UploadCreate> get serializer => _$UploadCreateSerializer();
}

class _$UploadCreateSerializer implements PrimitiveSerializer<UploadCreate> {
  @override
  final Iterable<Type> types = const [UploadCreate, _$UploadCreate];

  @override
  final String wireName = r'UploadCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UploadCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'fileName';
    yield serializers.serialize(
      object.fileName,
      specifiedType: const FullType(String),
    );
    yield r'sizeBytes';
    yield serializers.serialize(
      object.sizeBytes,
      specifiedType: const FullType(int),
    );
    yield r'mediaType';
    yield serializers.serialize(
      object.mediaType,
      specifiedType: const FullType(MediaType),
    );
    if (object.libraryPid != null) {
      yield r'libraryPid';
      yield serializers.serialize(
        object.libraryPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.sha256 != null) {
      yield r'sha256';
      yield serializers.serialize(
        object.sha256,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UploadCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UploadCreateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'fileName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fileName = valueDes;
          break;
        case r'sizeBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sizeBytes = valueDes;
          break;
        case r'mediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaType),
          ) as MediaType;
          result.mediaType = valueDes;
          break;
        case r'libraryPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.libraryPid = valueDes;
          break;
        case r'sha256':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sha256 = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UploadCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadCreateBuilder();
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

