//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'unfold_request.g.dart';

/// Folds of one entity type to forget.
///
/// Properties:
/// * [entityType] 
/// * [keys] - Fold keys exactly as `GET /library/folds` lists them.
@BuiltValue()
abstract class UnfoldRequest implements Built<UnfoldRequest, UnfoldRequestBuilder> {
  @BuiltValueField(wireName: r'entityType')
  UnfoldRequestEntityTypeEnum get entityType;
  // enum entityTypeEnum {  album,  artist,  release-group,  genre,  series,  };

  /// Fold keys exactly as `GET /library/folds` lists them.
  @BuiltValueField(wireName: r'keys')
  BuiltList<String> get keys;

  UnfoldRequest._();

  factory UnfoldRequest([void updates(UnfoldRequestBuilder b)]) = _$UnfoldRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UnfoldRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UnfoldRequest> get serializer => _$UnfoldRequestSerializer();
}

class _$UnfoldRequestSerializer implements PrimitiveSerializer<UnfoldRequest> {
  @override
  final Iterable<Type> types = const [UnfoldRequest, _$UnfoldRequest];

  @override
  final String wireName = r'UnfoldRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UnfoldRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entityType';
    yield serializers.serialize(
      object.entityType,
      specifiedType: const FullType(UnfoldRequestEntityTypeEnum),
    );
    yield r'keys';
    yield serializers.serialize(
      object.keys,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UnfoldRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UnfoldRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entityType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(UnfoldRequestEntityTypeEnum),
          ) as UnfoldRequestEntityTypeEnum;
          result.entityType = valueDes;
          break;
        case r'keys':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.keys.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UnfoldRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UnfoldRequestBuilder();
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


class UnfoldRequestEntityTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'album')
  static const UnfoldRequestEntityTypeEnum album = _$unfoldRequestEntityTypeEnum_album;
  @BuiltValueEnumConst(wireName: r'artist')
  static const UnfoldRequestEntityTypeEnum artist = _$unfoldRequestEntityTypeEnum_artist;
  @BuiltValueEnumConst(wireName: r'release-group')
  static const UnfoldRequestEntityTypeEnum releaseGroup = _$unfoldRequestEntityTypeEnum_releaseGroup;
  @BuiltValueEnumConst(wireName: r'genre')
  static const UnfoldRequestEntityTypeEnum genre = _$unfoldRequestEntityTypeEnum_genre;
  @BuiltValueEnumConst(wireName: r'series')
  static const UnfoldRequestEntityTypeEnum series = _$unfoldRequestEntityTypeEnum_series;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const UnfoldRequestEntityTypeEnum unknownDefaultOpenApi = _$unfoldRequestEntityTypeEnum_unknownDefaultOpenApi;

  static Serializer<UnfoldRequestEntityTypeEnum> get serializer => _$unfoldRequestEntityTypeEnumSerializer;

  const UnfoldRequestEntityTypeEnum._(String name): super(name);

  static BuiltSet<UnfoldRequestEntityTypeEnum> get values => _$unfoldRequestEntityTypeEnumValues;
  static UnfoldRequestEntityTypeEnum valueOf(String name) => _$unfoldRequestEntityTypeEnumValueOf(name);
}

