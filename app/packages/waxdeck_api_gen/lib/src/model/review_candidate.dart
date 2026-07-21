//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/candidate_pairing.dart';
import 'package:waxdeck_api_gen/src/model/candidate_component.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_candidate.g.dart';

/// One scored candidate release, ranked in the entry.
///
/// Properties:
/// * [mbid] - MusicBrainz release id.
/// * [releaseGroupMbid] - MusicBrainz release group id.
/// * [title] - Release title.
/// * [artist] - Release artist.
/// * [year] - Release year, 0 when unknown.
/// * [mediaCount] - Disc count, 0 when unknown.
/// * [trackCount] - Track count on the release.
/// * [country] - Release country.
/// * [label] - Label name.
/// * [catalogNumber] - Label catalog number.
/// * [compilation] - True for various-artists releases.
/// * [similarityPct] - Match quality in percent (0 to 100).
/// * [components] - The distance breakdown.
/// * [pairings] - Proposed track pairings.
/// * [missingTitles] - Titles of release tracks no file matched (the rip is missing them). 
/// * [extraTrackIndexes] - Indexes (into the entry's `tracks`) of files no release track matched (bonus or junk files). 
@BuiltValue()
abstract class ReviewCandidate implements Built<ReviewCandidate, ReviewCandidateBuilder> {
  /// MusicBrainz release id.
  @BuiltValueField(wireName: r'mbid')
  String get mbid;

  /// MusicBrainz release group id.
  @BuiltValueField(wireName: r'releaseGroupMbid')
  String? get releaseGroupMbid;

  /// Release title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Release artist.
  @BuiltValueField(wireName: r'artist')
  String get artist;

  /// Release year, 0 when unknown.
  @BuiltValueField(wireName: r'year')
  int? get year;

  /// Disc count, 0 when unknown.
  @BuiltValueField(wireName: r'mediaCount')
  int? get mediaCount;

  /// Track count on the release.
  @BuiltValueField(wireName: r'trackCount')
  int? get trackCount;

  /// Release country.
  @BuiltValueField(wireName: r'country')
  String? get country;

  /// Label name.
  @BuiltValueField(wireName: r'label')
  String? get label;

  /// Label catalog number.
  @BuiltValueField(wireName: r'catalogNumber')
  String? get catalogNumber;

  /// True for various-artists releases.
  @BuiltValueField(wireName: r'compilation')
  bool? get compilation;

  /// Match quality in percent (0 to 100).
  @BuiltValueField(wireName: r'similarityPct')
  double get similarityPct;

  /// The distance breakdown.
  @BuiltValueField(wireName: r'components')
  BuiltList<CandidateComponent>? get components;

  /// Proposed track pairings.
  @BuiltValueField(wireName: r'pairings')
  BuiltList<CandidatePairing> get pairings;

  /// Titles of release tracks no file matched (the rip is missing them). 
  @BuiltValueField(wireName: r'missingTitles')
  BuiltList<String>? get missingTitles;

  /// Indexes (into the entry's `tracks`) of files no release track matched (bonus or junk files). 
  @BuiltValueField(wireName: r'extraTrackIndexes')
  BuiltList<int>? get extraTrackIndexes;

  ReviewCandidate._();

  factory ReviewCandidate([void updates(ReviewCandidateBuilder b)]) = _$ReviewCandidate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewCandidateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewCandidate> get serializer => _$ReviewCandidateSerializer();
}

class _$ReviewCandidateSerializer implements PrimitiveSerializer<ReviewCandidate> {
  @override
  final Iterable<Type> types = const [ReviewCandidate, _$ReviewCandidate];

  @override
  final String wireName = r'ReviewCandidate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewCandidate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'mbid';
    yield serializers.serialize(
      object.mbid,
      specifiedType: const FullType(String),
    );
    if (object.releaseGroupMbid != null) {
      yield r'releaseGroupMbid';
      yield serializers.serialize(
        object.releaseGroupMbid,
        specifiedType: const FullType(String),
      );
    }
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    yield r'artist';
    yield serializers.serialize(
      object.artist,
      specifiedType: const FullType(String),
    );
    if (object.year != null) {
      yield r'year';
      yield serializers.serialize(
        object.year,
        specifiedType: const FullType(int),
      );
    }
    if (object.mediaCount != null) {
      yield r'mediaCount';
      yield serializers.serialize(
        object.mediaCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.trackCount != null) {
      yield r'trackCount';
      yield serializers.serialize(
        object.trackCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.country != null) {
      yield r'country';
      yield serializers.serialize(
        object.country,
        specifiedType: const FullType(String),
      );
    }
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType(String),
      );
    }
    if (object.catalogNumber != null) {
      yield r'catalogNumber';
      yield serializers.serialize(
        object.catalogNumber,
        specifiedType: const FullType(String),
      );
    }
    if (object.compilation != null) {
      yield r'compilation';
      yield serializers.serialize(
        object.compilation,
        specifiedType: const FullType(bool),
      );
    }
    yield r'similarityPct';
    yield serializers.serialize(
      object.similarityPct,
      specifiedType: const FullType(double),
    );
    if (object.components != null) {
      yield r'components';
      yield serializers.serialize(
        object.components,
        specifiedType: const FullType(BuiltList, [FullType(CandidateComponent)]),
      );
    }
    yield r'pairings';
    yield serializers.serialize(
      object.pairings,
      specifiedType: const FullType(BuiltList, [FullType(CandidatePairing)]),
    );
    if (object.missingTitles != null) {
      yield r'missingTitles';
      yield serializers.serialize(
        object.missingTitles,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.extraTrackIndexes != null) {
      yield r'extraTrackIndexes';
      yield serializers.serialize(
        object.extraTrackIndexes,
        specifiedType: const FullType(BuiltList, [FullType(int)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewCandidate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewCandidateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'mbid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mbid = valueDes;
          break;
        case r'releaseGroupMbid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.releaseGroupMbid = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'artist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artist = valueDes;
          break;
        case r'year':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.year = valueDes;
          break;
        case r'mediaCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.mediaCount = valueDes;
          break;
        case r'trackCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.trackCount = valueDes;
          break;
        case r'country':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.country = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.label = valueDes;
          break;
        case r'catalogNumber':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.catalogNumber = valueDes;
          break;
        case r'compilation':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.compilation = valueDes;
          break;
        case r'similarityPct':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.similarityPct = valueDes;
          break;
        case r'components':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(CandidateComponent)]),
          ) as BuiltList<CandidateComponent>;
          result.components.replace(valueDes);
          break;
        case r'pairings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(CandidatePairing)]),
          ) as BuiltList<CandidatePairing>;
          result.pairings.replace(valueDes);
          break;
        case r'missingTitles':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.missingTitles.replace(valueDes);
          break;
        case r'extraTrackIndexes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(int)]),
          ) as BuiltList<int>;
          result.extraTrackIndexes.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReviewCandidate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewCandidateBuilder();
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

