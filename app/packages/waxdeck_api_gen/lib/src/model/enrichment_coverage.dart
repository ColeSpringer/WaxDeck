//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/coverage_count.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_coverage.g.dart';

/// How much of the catalog has enriched.
///
/// Properties:
/// * [artists] 
/// * [releaseGroups] 
/// * [books] 
/// * [lyrics] 
@BuiltValue()
abstract class EnrichmentCoverage implements Built<EnrichmentCoverage, EnrichmentCoverageBuilder> {
  @BuiltValueField(wireName: r'artists')
  CoverageCount get artists;

  @BuiltValueField(wireName: r'releaseGroups')
  CoverageCount get releaseGroups;

  @BuiltValueField(wireName: r'books')
  CoverageCount get books;

  @BuiltValueField(wireName: r'lyrics')
  CoverageCount get lyrics;

  EnrichmentCoverage._();

  factory EnrichmentCoverage([void updates(EnrichmentCoverageBuilder b)]) = _$EnrichmentCoverage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentCoverageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentCoverage> get serializer => _$EnrichmentCoverageSerializer();
}

class _$EnrichmentCoverageSerializer implements PrimitiveSerializer<EnrichmentCoverage> {
  @override
  final Iterable<Type> types = const [EnrichmentCoverage, _$EnrichmentCoverage];

  @override
  final String wireName = r'EnrichmentCoverage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentCoverage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'artists';
    yield serializers.serialize(
      object.artists,
      specifiedType: const FullType(CoverageCount),
    );
    yield r'releaseGroups';
    yield serializers.serialize(
      object.releaseGroups,
      specifiedType: const FullType(CoverageCount),
    );
    yield r'books';
    yield serializers.serialize(
      object.books,
      specifiedType: const FullType(CoverageCount),
    );
    yield r'lyrics';
    yield serializers.serialize(
      object.lyrics,
      specifiedType: const FullType(CoverageCount),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentCoverage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentCoverageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'artists':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CoverageCount),
          ) as CoverageCount;
          result.artists.replace(valueDes);
          break;
        case r'releaseGroups':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CoverageCount),
          ) as CoverageCount;
          result.releaseGroups.replace(valueDes);
          break;
        case r'books':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CoverageCount),
          ) as CoverageCount;
          result.books.replace(valueDes);
          break;
        case r'lyrics':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CoverageCount),
          ) as CoverageCount;
          result.lyrics.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentCoverage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentCoverageBuilder();
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

