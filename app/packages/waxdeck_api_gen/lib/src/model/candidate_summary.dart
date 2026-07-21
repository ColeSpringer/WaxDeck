//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'candidate_summary.g.dart';

/// The ranked-best candidate in one line.
///
/// Properties:
/// * [mbid] - MusicBrainz release id.
/// * [title] - Release title.
/// * [artist] - Release artist.
/// * [year] - Release year, 0 when unknown.
/// * [similarityPct] - Match quality in percent (0 to 100).
@BuiltValue()
abstract class CandidateSummary implements Built<CandidateSummary, CandidateSummaryBuilder> {
  /// MusicBrainz release id.
  @BuiltValueField(wireName: r'mbid')
  String get mbid;

  /// Release title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Release artist.
  @BuiltValueField(wireName: r'artist')
  String get artist;

  /// Release year, 0 when unknown.
  @BuiltValueField(wireName: r'year')
  int? get year;

  /// Match quality in percent (0 to 100).
  @BuiltValueField(wireName: r'similarityPct')
  double get similarityPct;

  CandidateSummary._();

  factory CandidateSummary([void updates(CandidateSummaryBuilder b)]) = _$CandidateSummary;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CandidateSummaryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CandidateSummary> get serializer => _$CandidateSummarySerializer();
}

class _$CandidateSummarySerializer implements PrimitiveSerializer<CandidateSummary> {
  @override
  final Iterable<Type> types = const [CandidateSummary, _$CandidateSummary];

  @override
  final String wireName = r'CandidateSummary';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CandidateSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'mbid';
    yield serializers.serialize(
      object.mbid,
      specifiedType: const FullType(String),
    );
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
    yield r'similarityPct';
    yield serializers.serialize(
      object.similarityPct,
      specifiedType: const FullType(double),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CandidateSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CandidateSummaryBuilder result,
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
        case r'similarityPct':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.similarityPct = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CandidateSummary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CandidateSummaryBuilder();
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

