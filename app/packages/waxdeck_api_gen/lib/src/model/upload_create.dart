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
/// * [sizeBytes] - Total file size in bytes. The maximum is the largest single file WaxDeck accepts - 16 GiB, clear of even a long hi-res or DSD single-file release - and a session declaring more answers `invalid-request` rather than opening. What is actually accepted is still bounded by the caller's quota and by the room on the server's staging volume. 
/// * [mediaType] 
/// * [libraryPid] - The library this upload belongs to, from `GET /uploads/targets`. It selects the library whose matching mode and singles auto-apply setting govern the import, and whose read-only state gates it; it does not choose where the file is placed, which is the catalog's own routing by media type into a managed root. Omitted, the entry belongs to no named library and per-library settings fall back to the one library that could hold its media, staying off where that is ambiguous. 
/// * [sha256] - Lowercase hex SHA-256 of the file, for the up-front exact duplicate warning and the completion integrity check. 
/// * [batchId] - Joins the session to an open upload batch owned by the caller; its grouping intent then decides how this file reaches the review queue. The session must declare the batch's media type and library. Referencing a batch that is not open, or not the caller's, or mismatching either field, answers `invalid-request`. 
/// * [batchPath] - The file's directory relative to the picked or dropped folder, forward-slash separated (empty or absent for a file at the top). The `auto` grouping clusters by it, so disc subfolders (`CD1`, `Disc 2`) fold into one album. Must stay relative - absolute paths and `..` segments are rejected, as is passing it without `batchId`. `fileName` stays a bare name regardless. 
/// * [identify] - Whether the file is identified against MusicBrainz. Absent means the account's own default (`identifyOptOut` in preferences), which is why there is no schema default here: a generated client that filled one in would erase the account setting on every upload.  Declining means the file enters the library as delivered, with no stop: completing the session imports it and files its review entry `as-is` in one step, so nothing waits for a decision that was already made at submission. The entry is still written, decided rather than pending, so the import leaves the same record as a hand-decided `as-is` one; like any `as-is` it does not revert, so undoing it means deleting the item from the library. If the import cannot proceed - a read-only destination, a name collision, a file the server already flagged as a duplicate - the entry is left pending for a person instead, carrying `identifyDeclined`.  Ignored on a batch member: the batch's own value decides for every file in it. 
@BuiltValue()
abstract class UploadCreate implements Built<UploadCreate, UploadCreateBuilder> {
  /// The file's name (base name only; any path is rejected). The extension picks the accepted-format check. 
  @BuiltValueField(wireName: r'fileName')
  String get fileName;

  /// Total file size in bytes. The maximum is the largest single file WaxDeck accepts - 16 GiB, clear of even a long hi-res or DSD single-file release - and a session declaring more answers `invalid-request` rather than opening. What is actually accepted is still bounded by the caller's quota and by the room on the server's staging volume. 
  @BuiltValueField(wireName: r'sizeBytes')
  int get sizeBytes;

  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  /// The library this upload belongs to, from `GET /uploads/targets`. It selects the library whose matching mode and singles auto-apply setting govern the import, and whose read-only state gates it; it does not choose where the file is placed, which is the catalog's own routing by media type into a managed root. Omitted, the entry belongs to no named library and per-library settings fall back to the one library that could hold its media, staying off where that is ambiguous. 
  @BuiltValueField(wireName: r'libraryPid')
  String? get libraryPid;

  /// Lowercase hex SHA-256 of the file, for the up-front exact duplicate warning and the completion integrity check. 
  @BuiltValueField(wireName: r'sha256')
  String? get sha256;

  /// Joins the session to an open upload batch owned by the caller; its grouping intent then decides how this file reaches the review queue. The session must declare the batch's media type and library. Referencing a batch that is not open, or not the caller's, or mismatching either field, answers `invalid-request`. 
  @BuiltValueField(wireName: r'batchId')
  String? get batchId;

  /// The file's directory relative to the picked or dropped folder, forward-slash separated (empty or absent for a file at the top). The `auto` grouping clusters by it, so disc subfolders (`CD1`, `Disc 2`) fold into one album. Must stay relative - absolute paths and `..` segments are rejected, as is passing it without `batchId`. `fileName` stays a bare name regardless. 
  @BuiltValueField(wireName: r'batchPath')
  String? get batchPath;

  /// Whether the file is identified against MusicBrainz. Absent means the account's own default (`identifyOptOut` in preferences), which is why there is no schema default here: a generated client that filled one in would erase the account setting on every upload.  Declining means the file enters the library as delivered, with no stop: completing the session imports it and files its review entry `as-is` in one step, so nothing waits for a decision that was already made at submission. The entry is still written, decided rather than pending, so the import leaves the same record as a hand-decided `as-is` one; like any `as-is` it does not revert, so undoing it means deleting the item from the library. If the import cannot proceed - a read-only destination, a name collision, a file the server already flagged as a duplicate - the entry is left pending for a person instead, carrying `identifyDeclined`.  Ignored on a batch member: the batch's own value decides for every file in it. 
  @BuiltValueField(wireName: r'identify')
  bool? get identify;

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
    if (object.batchId != null) {
      yield r'batchId';
      yield serializers.serialize(
        object.batchId,
        specifiedType: const FullType(String),
      );
    }
    if (object.batchPath != null) {
      yield r'batchPath';
      yield serializers.serialize(
        object.batchPath,
        specifiedType: const FullType(String),
      );
    }
    if (object.identify != null) {
      yield r'identify';
      yield serializers.serialize(
        object.identify,
        specifiedType: const FullType(bool),
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
        case r'batchId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.batchId = valueDes;
          break;
        case r'batchPath':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.batchPath = valueDes;
          break;
        case r'identify':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.identify = valueDes;
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

