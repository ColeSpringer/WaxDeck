//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/month_listening.dart';
import 'package:waxdeck_api_gen/src/model/media_type_listening.dart';
import 'package:waxdeck_api_gen/src/model/top_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'year_in_review.g.dart';

/// One user's listening recap for one calendar year, computed in the caller's preferred timezone. 
///
/// Properties:
/// * [year] - The calendar year.
/// * [timezone] - IANA timezone the recap was computed in.
/// * [totalMs] - Total milliseconds listened that year.
/// * [sessions] - Listen sessions that year.
/// * [distinctItems] - Distinct tracks, episodes, and books played that year.
/// * [newInLibrary] - Items that joined the library that year.
/// * [timeSavedMs] - Milliseconds saved by silence trimming and speed-up that year, as reported by clients. 
/// * [longestStreakDays] - The year's longest run of consecutive listening days.
/// * [byMonth] - Month-by-month listening, January first. All twelve months are present, zeros included, so clients chart the year's shape directly. 
/// * [byMediaType] - Listening split by media type, most-listened first.
/// * [topArtists] - Most-listened music artists that year.
/// * [topTracks] - Most-listened tracks that year.
/// * [topGenres] - Most-listened music genres that year.
/// * [topShows] - Most-listened podcast shows that year.
@BuiltValue()
abstract class YearInReview implements Built<YearInReview, YearInReviewBuilder> {
  /// The calendar year.
  @BuiltValueField(wireName: r'year')
  int get year;

  /// IANA timezone the recap was computed in.
  @BuiltValueField(wireName: r'timezone')
  String get timezone;

  /// Total milliseconds listened that year.
  @BuiltValueField(wireName: r'totalMs')
  int get totalMs;

  /// Listen sessions that year.
  @BuiltValueField(wireName: r'sessions')
  int get sessions;

  /// Distinct tracks, episodes, and books played that year.
  @BuiltValueField(wireName: r'distinctItems')
  int get distinctItems;

  /// Items that joined the library that year.
  @BuiltValueField(wireName: r'newInLibrary')
  int get newInLibrary;

  /// Milliseconds saved by silence trimming and speed-up that year, as reported by clients. 
  @BuiltValueField(wireName: r'timeSavedMs')
  int get timeSavedMs;

  /// The year's longest run of consecutive listening days.
  @BuiltValueField(wireName: r'longestStreakDays')
  int get longestStreakDays;

  /// Month-by-month listening, January first. All twelve months are present, zeros included, so clients chart the year's shape directly. 
  @BuiltValueField(wireName: r'byMonth')
  BuiltList<MonthListening> get byMonth;

  /// Listening split by media type, most-listened first.
  @BuiltValueField(wireName: r'byMediaType')
  BuiltList<MediaTypeListening> get byMediaType;

  /// Most-listened music artists that year.
  @BuiltValueField(wireName: r'topArtists')
  BuiltList<TopEntry> get topArtists;

  /// Most-listened tracks that year.
  @BuiltValueField(wireName: r'topTracks')
  BuiltList<TopEntry> get topTracks;

  /// Most-listened music genres that year.
  @BuiltValueField(wireName: r'topGenres')
  BuiltList<TopEntry> get topGenres;

  /// Most-listened podcast shows that year.
  @BuiltValueField(wireName: r'topShows')
  BuiltList<TopEntry> get topShows;

  YearInReview._();

  factory YearInReview([void updates(YearInReviewBuilder b)]) = _$YearInReview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(YearInReviewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<YearInReview> get serializer => _$YearInReviewSerializer();
}

class _$YearInReviewSerializer implements PrimitiveSerializer<YearInReview> {
  @override
  final Iterable<Type> types = const [YearInReview, _$YearInReview];

  @override
  final String wireName = r'YearInReview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    YearInReview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'year';
    yield serializers.serialize(
      object.year,
      specifiedType: const FullType(int),
    );
    yield r'timezone';
    yield serializers.serialize(
      object.timezone,
      specifiedType: const FullType(String),
    );
    yield r'totalMs';
    yield serializers.serialize(
      object.totalMs,
      specifiedType: const FullType(int),
    );
    yield r'sessions';
    yield serializers.serialize(
      object.sessions,
      specifiedType: const FullType(int),
    );
    yield r'distinctItems';
    yield serializers.serialize(
      object.distinctItems,
      specifiedType: const FullType(int),
    );
    yield r'newInLibrary';
    yield serializers.serialize(
      object.newInLibrary,
      specifiedType: const FullType(int),
    );
    yield r'timeSavedMs';
    yield serializers.serialize(
      object.timeSavedMs,
      specifiedType: const FullType(int),
    );
    yield r'longestStreakDays';
    yield serializers.serialize(
      object.longestStreakDays,
      specifiedType: const FullType(int),
    );
    yield r'byMonth';
    yield serializers.serialize(
      object.byMonth,
      specifiedType: const FullType(BuiltList, [FullType(MonthListening)]),
    );
    yield r'byMediaType';
    yield serializers.serialize(
      object.byMediaType,
      specifiedType: const FullType(BuiltList, [FullType(MediaTypeListening)]),
    );
    yield r'topArtists';
    yield serializers.serialize(
      object.topArtists,
      specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
    );
    yield r'topTracks';
    yield serializers.serialize(
      object.topTracks,
      specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
    );
    yield r'topGenres';
    yield serializers.serialize(
      object.topGenres,
      specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
    );
    yield r'topShows';
    yield serializers.serialize(
      object.topShows,
      specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    YearInReview object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required YearInReviewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'year':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.year = valueDes;
          break;
        case r'timezone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.timezone = valueDes;
          break;
        case r'totalMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalMs = valueDes;
          break;
        case r'sessions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sessions = valueDes;
          break;
        case r'distinctItems':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.distinctItems = valueDes;
          break;
        case r'newInLibrary':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.newInLibrary = valueDes;
          break;
        case r'timeSavedMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.timeSavedMs = valueDes;
          break;
        case r'longestStreakDays':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.longestStreakDays = valueDes;
          break;
        case r'byMonth':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(MonthListening)]),
          ) as BuiltList<MonthListening>;
          result.byMonth.replace(valueDes);
          break;
        case r'byMediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(MediaTypeListening)]),
          ) as BuiltList<MediaTypeListening>;
          result.byMediaType.replace(valueDes);
          break;
        case r'topArtists':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
          ) as BuiltList<TopEntry>;
          result.topArtists.replace(valueDes);
          break;
        case r'topTracks':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
          ) as BuiltList<TopEntry>;
          result.topTracks.replace(valueDes);
          break;
        case r'topGenres':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
          ) as BuiltList<TopEntry>;
          result.topGenres.replace(valueDes);
          break;
        case r'topShows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
          ) as BuiltList<TopEntry>;
          result.topShows.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  YearInReview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = YearInReviewBuilder();
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

