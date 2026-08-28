//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:waxdeck_api_gen/src/model/upload_grouping.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_batch_create.g.dart';

/// A new upload batch.
///
/// Properties:
/// * [grouping] 
/// * [mediaType] 
/// * [libraryPid] - The library every member belongs to; see `UploadCreate` for what naming one selects. Members re-declare it at session creation and must match (a differing member value answers `invalid-request`). 
/// * [identify] - Whether the batch's files are identified against MusicBrainz. Absent means the account's own default (`identifyOptOut` in preferences); see `UploadCreate` for why there is no schema default, and for what declining does. Decided once here and applied to every entry the batch opens, so a member's own value is ignored. 
@BuiltValue()
abstract class UploadBatchCreate implements Built<UploadBatchCreate, UploadBatchCreateBuilder> {
  @BuiltValueField(wireName: r'grouping')
  UploadGrouping get grouping;
  // enum groupingEnum {  auto,  album,  tracks,  };

  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  /// The library every member belongs to; see `UploadCreate` for what naming one selects. Members re-declare it at session creation and must match (a differing member value answers `invalid-request`). 
  @BuiltValueField(wireName: r'libraryPid')
  String? get libraryPid;

  /// Whether the batch's files are identified against MusicBrainz. Absent means the account's own default (`identifyOptOut` in preferences); see `UploadCreate` for why there is no schema default, and for what declining does. Decided once here and applied to every entry the batch opens, so a member's own value is ignored. 
  @BuiltValueField(wireName: r'identify')
  bool? get identify;

  UploadBatchCreate._();

  factory UploadBatchCreate([void updates(UploadBatchCreateBuilder b)]) = _$UploadBatchCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadBatchCreateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UploadBatchCreate> get serializer => _$UploadBatchCreateSerializer();
}

class _$UploadBatchCreateSerializer implements PrimitiveSerializer<UploadBatchCreate> {
  @override
  final Iterable<Type> types = const [UploadBatchCreate, _$UploadBatchCreate];

  @override
  final String wireName = r'UploadBatchCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UploadBatchCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    UploadBatchCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UploadBatchCreateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
  UploadBatchCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadBatchCreateBuilder();
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

