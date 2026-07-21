//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'merge_request.g.dart';

/// A duplicate entity merge.
///
/// Properties:
/// * [entityType] - What is being merged.
/// * [survivorPid] - The entity that keeps its pid.
/// * [loserPids] - The entities merged into the survivor.
@BuiltValue()
abstract class MergeRequest implements Built<MergeRequest, MergeRequestBuilder> {
  /// What is being merged.
  @BuiltValueField(wireName: r'entityType')
  MergeRequestEntityTypeEnum get entityType;
  // enum entityTypeEnum {  album,  artist,  release-group,  genre,  };

  /// The entity that keeps its pid.
  @BuiltValueField(wireName: r'survivorPid')
  String get survivorPid;

  /// The entities merged into the survivor.
  @BuiltValueField(wireName: r'loserPids')
  BuiltList<String> get loserPids;

  MergeRequest._();

  factory MergeRequest([void updates(MergeRequestBuilder b)]) = _$MergeRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MergeRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MergeRequest> get serializer => _$MergeRequestSerializer();
}

class _$MergeRequestSerializer implements PrimitiveSerializer<MergeRequest> {
  @override
  final Iterable<Type> types = const [MergeRequest, _$MergeRequest];

  @override
  final String wireName = r'MergeRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MergeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entityType';
    yield serializers.serialize(
      object.entityType,
      specifiedType: const FullType(MergeRequestEntityTypeEnum),
    );
    yield r'survivorPid';
    yield serializers.serialize(
      object.survivorPid,
      specifiedType: const FullType(String),
    );
    yield r'loserPids';
    yield serializers.serialize(
      object.loserPids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MergeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MergeRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entityType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MergeRequestEntityTypeEnum),
          ) as MergeRequestEntityTypeEnum;
          result.entityType = valueDes;
          break;
        case r'survivorPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.survivorPid = valueDes;
          break;
        case r'loserPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.loserPids.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MergeRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MergeRequestBuilder();
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

class MergeRequestEntityTypeEnum extends EnumClass {

  /// What is being merged.
  @BuiltValueEnumConst(wireName: r'album')
  static const MergeRequestEntityTypeEnum album = _$mergeRequestEntityTypeEnum_album;
  /// What is being merged.
  @BuiltValueEnumConst(wireName: r'artist')
  static const MergeRequestEntityTypeEnum artist = _$mergeRequestEntityTypeEnum_artist;
  /// What is being merged.
  @BuiltValueEnumConst(wireName: r'release-group')
  static const MergeRequestEntityTypeEnum releaseGroup = _$mergeRequestEntityTypeEnum_releaseGroup;
  /// What is being merged.
  @BuiltValueEnumConst(wireName: r'genre')
  static const MergeRequestEntityTypeEnum genre = _$mergeRequestEntityTypeEnum_genre;

  static Serializer<MergeRequestEntityTypeEnum> get serializer => _$mergeRequestEntityTypeEnumSerializer;

  const MergeRequestEntityTypeEnum._(String name): super(name);

  static BuiltSet<MergeRequestEntityTypeEnum> get values => _$mergeRequestEntityTypeEnumValues;
  static MergeRequestEntityTypeEnum valueOf(String name) => _$mergeRequestEntityTypeEnumValueOf(name);
}

