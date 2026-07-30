//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:waxdeck_api_gen/src/model/duplicate_warning.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload.g.dart';

/// One upload session.
///
/// Properties:
/// * [id] - Upload pid.
/// * [fileName] - The declared file name.
/// * [sizeBytes] - Declared total size.
/// * [receivedBytes] - Bytes stored so far; resume by sending the next chunk at this offset. 
/// * [mediaType] 
/// * [libraryPid] - Target library.
/// * [state] - Session state: `receiving` (bytes still arriving), `staged` (complete, in the review pipeline), `imported` (its file entered the library), or `discarded`. A string, not a closed enum. 
/// * [reviewEntryId] - The review entry the file landed in. Opened at completion for a solo session; for a batch member, filled when the batch finalizes - or at its own completion, for a member that finished only after the batch closed. 
/// * [batchId] - The batch the session joined, if any.
/// * [duplicate] 
/// * [uploadedBy] - The uploader's user pid (admin listings).
/// * [createdAt] - When the session was created.
/// * [expiresAt] - When an unfinished session and its bytes are reclaimed. 
@BuiltValue()
abstract class Upload implements Built<Upload, UploadBuilder> {
  /// Upload pid.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// The declared file name.
  @BuiltValueField(wireName: r'fileName')
  String get fileName;

  /// Declared total size.
  @BuiltValueField(wireName: r'sizeBytes')
  int get sizeBytes;

  /// Bytes stored so far; resume by sending the next chunk at this offset. 
  @BuiltValueField(wireName: r'receivedBytes')
  int get receivedBytes;

  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  /// Target library.
  @BuiltValueField(wireName: r'libraryPid')
  String? get libraryPid;

  /// Session state: `receiving` (bytes still arriving), `staged` (complete, in the review pipeline), `imported` (its file entered the library), or `discarded`. A string, not a closed enum. 
  @BuiltValueField(wireName: r'state')
  String get state;

  /// The review entry the file landed in. Opened at completion for a solo session; for a batch member, filled when the batch finalizes - or at its own completion, for a member that finished only after the batch closed. 
  @BuiltValueField(wireName: r'reviewEntryId')
  String? get reviewEntryId;

  /// The batch the session joined, if any.
  @BuiltValueField(wireName: r'batchId')
  String? get batchId;

  @BuiltValueField(wireName: r'duplicate')
  DuplicateWarning? get duplicate;

  /// The uploader's user pid (admin listings).
  @BuiltValueField(wireName: r'uploadedBy')
  String? get uploadedBy;

  /// When the session was created.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  /// When an unfinished session and its bytes are reclaimed. 
  @BuiltValueField(wireName: r'expiresAt')
  DateTime? get expiresAt;

  Upload._();

  factory Upload([void updates(UploadBuilder b)]) = _$Upload;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Upload> get serializer => _$UploadSerializer();
}

class _$UploadSerializer implements PrimitiveSerializer<Upload> {
  @override
  final Iterable<Type> types = const [Upload, _$Upload];

  @override
  final String wireName = r'Upload';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Upload object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
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
    yield r'receivedBytes';
    yield serializers.serialize(
      object.receivedBytes,
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
    yield r'state';
    yield serializers.serialize(
      object.state,
      specifiedType: const FullType(String),
    );
    if (object.reviewEntryId != null) {
      yield r'reviewEntryId';
      yield serializers.serialize(
        object.reviewEntryId,
        specifiedType: const FullType(String),
      );
    }
    if (object.batchId != null) {
      yield r'batchId';
      yield serializers.serialize(
        object.batchId,
        specifiedType: const FullType(String),
      );
    }
    if (object.duplicate != null) {
      yield r'duplicate';
      yield serializers.serialize(
        object.duplicate,
        specifiedType: const FullType(DuplicateWarning),
      );
    }
    if (object.uploadedBy != null) {
      yield r'uploadedBy';
      yield serializers.serialize(
        object.uploadedBy,
        specifiedType: const FullType(String),
      );
    }
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.expiresAt != null) {
      yield r'expiresAt';
      yield serializers.serialize(
        object.expiresAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Upload object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UploadBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
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
        case r'receivedBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.receivedBytes = valueDes;
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
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.state = valueDes;
          break;
        case r'reviewEntryId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reviewEntryId = valueDes;
          break;
        case r'batchId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.batchId = valueDes;
          break;
        case r'duplicate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DuplicateWarning),
          ) as DuplicateWarning;
          result.duplicate.replace(valueDes);
          break;
        case r'uploadedBy':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.uploadedBy = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Upload deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadBuilder();
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

