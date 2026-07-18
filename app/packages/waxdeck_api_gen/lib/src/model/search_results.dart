//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/search_hit.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'search_results.g.dart';

/// Search results grouped by kind, ranked within each group.
///
/// Properties:
/// * [query] - The query these results answer.
/// * [artists] 
/// * [albums] 
/// * [tracks] 
/// * [books] 
/// * [episodes] 
/// * [truncated] - True when any group was capped at the limit.
@BuiltValue()
abstract class SearchResults implements Built<SearchResults, SearchResultsBuilder> {
  /// The query these results answer.
  @BuiltValueField(wireName: r'query')
  String get query;

  @BuiltValueField(wireName: r'artists')
  BuiltList<SearchHit> get artists;

  @BuiltValueField(wireName: r'albums')
  BuiltList<SearchHit> get albums;

  @BuiltValueField(wireName: r'tracks')
  BuiltList<SearchHit> get tracks;

  @BuiltValueField(wireName: r'books')
  BuiltList<SearchHit> get books;

  @BuiltValueField(wireName: r'episodes')
  BuiltList<SearchHit> get episodes;

  /// True when any group was capped at the limit.
  @BuiltValueField(wireName: r'truncated')
  bool? get truncated;

  SearchResults._();

  factory SearchResults([void updates(SearchResultsBuilder b)]) = _$SearchResults;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SearchResultsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SearchResults> get serializer => _$SearchResultsSerializer();
}

class _$SearchResultsSerializer implements PrimitiveSerializer<SearchResults> {
  @override
  final Iterable<Type> types = const [SearchResults, _$SearchResults];

  @override
  final String wireName = r'SearchResults';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SearchResults object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'query';
    yield serializers.serialize(
      object.query,
      specifiedType: const FullType(String),
    );
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
    yield r'tracks';
    yield serializers.serialize(
      object.tracks,
      specifiedType: const FullType(BuiltList, [FullType(SearchHit)]),
    );
    yield r'books';
    yield serializers.serialize(
      object.books,
      specifiedType: const FullType(BuiltList, [FullType(SearchHit)]),
    );
    yield r'episodes';
    yield serializers.serialize(
      object.episodes,
      specifiedType: const FullType(BuiltList, [FullType(SearchHit)]),
    );
    if (object.truncated != null) {
      yield r'truncated';
      yield serializers.serialize(
        object.truncated,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SearchResults object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SearchResultsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'query':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.query = valueDes;
          break;
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
        case r'tracks':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(SearchHit)]),
          ) as BuiltList<SearchHit>;
          result.tracks.replace(valueDes);
          break;
        case r'books':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(SearchHit)]),
          ) as BuiltList<SearchHit>;
          result.books.replace(valueDes);
          break;
        case r'episodes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(SearchHit)]),
          ) as BuiltList<SearchHit>;
          result.episodes.replace(valueDes);
          break;
        case r'truncated':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.truncated = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SearchResults deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SearchResultsBuilder();
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

