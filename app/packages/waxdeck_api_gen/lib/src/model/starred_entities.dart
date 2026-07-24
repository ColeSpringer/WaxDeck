//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/search_hit.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'starred_entities.g.dart';

/// The caller's starred catalog entities, grouped by kind.
///
/// Properties:
/// * [artists] 
/// * [albums] 
@BuiltValue()
abstract class StarredEntities implements Built<StarredEntities, StarredEntitiesBuilder> {
  @BuiltValueField(wireName: r'artists')
  BuiltList<SearchHit> get artists;

  @BuiltValueField(wireName: r'albums')
  BuiltList<SearchHit> get albums;

  StarredEntities._();

  factory StarredEntities([void updates(StarredEntitiesBuilder b)]) = _$StarredEntities;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(StarredEntitiesBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<StarredEntities> get serializer => _$StarredEntitiesSerializer();
}

class _$StarredEntitiesSerializer implements PrimitiveSerializer<StarredEntities> {
  @override
  final Iterable<Type> types = const [StarredEntities, _$StarredEntities];

  @override
  final String wireName = r'StarredEntities';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    StarredEntities object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'artists';
    yield serializers.serialize(
      object.artists,
      specifiedType: const FullType(BuiltList, [FullType(SearchHit)]),
    );
    yield r'albums';
    yield serializers.serialize(
      object.albums,
      specifiedType: const FullType(BuiltList, [FullType(SearchHit)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    StarredEntities object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required StarredEntitiesBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'artists':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(SearchHit)]),
          ) as BuiltList<SearchHit>;
          result.artists.replace(valueDes);
          break;
        case r'albums':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(SearchHit)]),
          ) as BuiltList<SearchHit>;
          result.albums.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  StarredEntities deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = StarredEntitiesBuilder();
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

