//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:waxdeck_api_gen/src/model/upload_grouping.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_batch.g.dart';

/// One upload batch.
///
/// Properties:
/// * [id] - Batch pid.
/// * [grouping] 
/// * [mediaType] 
/// * [libraryPid] - Target library.
/// * [state] - Batch state: `open` (accepting members), `finalized` (the finalize call grouped its members), or `expired` (the 24-hour window lapsed and the server finalized it with what had arrived). A string, not a closed enum. 
/// * [reviewEntryIds] - The review entries finalization opened; empty until the batch closes, and empty on a batch whose every member was deleted before finalizing. 
/// * [createdAt] - When the batch was opened.
/// * [expiresAt] - The deadline after which the server may auto-finalize an open batch with the members staged by then (a background sweep, so an overdue batch can stay open a little past this). 
@BuiltValue()
abstract class UploadBatch implements Built<UploadBatch, UploadBatchBuilder> {
  /// Batch pid.
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'grouping')
  UploadGrouping get grouping;
  // enum groupingEnum {  auto,  album,  tracks,  };

  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  /// Target library.
  @BuiltValueField(wireName: r'libraryPid')
  String? get libraryPid;

  /// Batch state: `open` (accepting members), `finalized` (the finalize call grouped its members), or `expired` (the 24-hour window lapsed and the server finalized it with what had arrived). A string, not a closed enum. 
  @BuiltValueField(wireName: r'state')
  String get state;

  /// The review entries finalization opened; empty until the batch closes, and empty on a batch whose every member was deleted before finalizing. 
  @BuiltValueField(wireName: r'reviewEntryIds')
  BuiltList<String> get reviewEntryIds;

  /// When the batch was opened.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  /// The deadline after which the server may auto-finalize an open batch with the members staged by then (a background sweep, so an overdue batch can stay open a little past this). 
  @BuiltValueField(wireName: r'expiresAt')
  DateTime get expiresAt;

  UploadBatch._();

  factory UploadBatch([void updates(UploadBatchBuilder b)]) = _$UploadBatch;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadBatchBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UploadBatch> get serializer => _$UploadBatchSerializer();
}

class _$UploadBatchSerializer implements PrimitiveSerializer<UploadBatch> {
  @override
  final Iterable<Type> types = const [UploadBatch, _$UploadBatch];

  @override
  final String wireName = r'UploadBatch';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UploadBatch object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'grouping';
    yield serializers.serialize(
      object.grouping,
      specifiedType: const FullType(UploadGrouping),
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
    yield r'reviewEntryIds';
    yield serializers.serialize(
      object.reviewEntryIds,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'expiresAt';
    yield serializers.serialize(
      object.expiresAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UploadBatch object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UploadBatchBuilder result,
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
        case r'grouping':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(UploadGrouping),
          ) as UploadGrouping;
          result.grouping = valueDes;
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
        case r'reviewEntryIds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.reviewEntryIds.replace(valueDes);
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
  UploadBatch deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadBatchBuilder();
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

