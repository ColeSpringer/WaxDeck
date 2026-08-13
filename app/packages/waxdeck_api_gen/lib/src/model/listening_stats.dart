//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/listening_bucket.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/media_type_listening.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'listening_stats.g.dart';

/// Aggregated listening time for one user.
///
/// Properties:
/// * [range] - The range that was aggregated.
/// * [bucket] - The bucket size used.
/// * [timezone] - IANA timezone the calendar bucketing used (the caller's preference, `UTC` when unset). 
/// * [totalMs] - Total milliseconds listened in the range.
/// * [sessions] - Listen sessions in the range.
/// * [timeSavedMs] - Milliseconds saved by silence trimming and speed-up in the range, as reported by clients. 
/// * [buckets] - Chart buckets, oldest first. Empty buckets are omitted.
/// * [byMediaType] - Listening split by media type, most-listened first.
@BuiltValue()
abstract class ListeningStats implements Built<ListeningStats, ListeningStatsBuilder> {
  /// The range that was aggregated.
  @BuiltValueField(wireName: r'range')
  ListeningStatsRangeEnum get range;
  // enum rangeEnum {  7d,  30d,  90d,  365d,  all,  };

  /// The bucket size used.
  @BuiltValueField(wireName: r'bucket')
  ListeningStatsBucketEnum get bucket;
  // enum bucketEnum {  day,  week,  month,  };

  /// IANA timezone the calendar bucketing used (the caller's preference, `UTC` when unset). 
  @BuiltValueField(wireName: r'timezone')
  String get timezone;

  /// Total milliseconds listened in the range.
  @BuiltValueField(wireName: r'totalMs')
  int get totalMs;

  /// Listen sessions in the range.
  @BuiltValueField(wireName: r'sessions')
  int get sessions;

  /// Milliseconds saved by silence trimming and speed-up in the range, as reported by clients. 
  @BuiltValueField(wireName: r'timeSavedMs')
  int get timeSavedMs;

  /// Chart buckets, oldest first. Empty buckets are omitted.
  @BuiltValueField(wireName: r'buckets')
  BuiltList<ListeningBucket> get buckets;

  /// Listening split by media type, most-listened first.
  @BuiltValueField(wireName: r'byMediaType')
  BuiltList<MediaTypeListening> get byMediaType;

  ListeningStats._();

  factory ListeningStats([void updates(ListeningStatsBuilder b)]) = _$ListeningStats;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListeningStatsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListeningStats> get serializer => _$ListeningStatsSerializer();
}

class _$ListeningStatsSerializer implements PrimitiveSerializer<ListeningStats> {
  @override
  final Iterable<Type> types = const [ListeningStats, _$ListeningStats];

  @override
  final String wireName = r'ListeningStats';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListeningStats object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'range';
    yield serializers.serialize(
      object.range,
      specifiedType: const FullType(ListeningStatsRangeEnum),
    );
    yield r'bucket';
    yield serializers.serialize(
      object.bucket,
      specifiedType: const FullType(ListeningStatsBucketEnum),
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
    yield r'timeSavedMs';
    yield serializers.serialize(
      object.timeSavedMs,
      specifiedType: const FullType(int),
    );
    yield r'buckets';
    yield serializers.serialize(
      object.buckets,
      specifiedType: const FullType(BuiltList, [FullType(ListeningBucket)]),
    );
    yield r'byMediaType';
    yield serializers.serialize(
      object.byMediaType,
      specifiedType: const FullType(BuiltList, [FullType(MediaTypeListening)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ListeningStats object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListeningStatsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'range':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ListeningStatsRangeEnum),
          ) as ListeningStatsRangeEnum;
          result.range = valueDes;
          break;
        case r'bucket':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ListeningStatsBucketEnum),
          ) as ListeningStatsBucketEnum;
          result.bucket = valueDes;
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
        case r'timeSavedMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.timeSavedMs = valueDes;
          break;
        case r'buckets':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ListeningBucket)]),
          ) as BuiltList<ListeningBucket>;
          result.buckets.replace(valueDes);
          break;
        case r'byMediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(MediaTypeListening)]),
          ) as BuiltList<MediaTypeListening>;
          result.byMediaType.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ListeningStats deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListeningStatsBuilder();
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

class ListeningStatsRangeEnum extends EnumClass {

  /// The range that was aggregated.
  @BuiltValueEnumConst(wireName: r'7d')
  static const ListeningStatsRangeEnum n7d = _$listeningStatsRangeEnum_n7d;
  /// The range that was aggregated.
  @BuiltValueEnumConst(wireName: r'30d')
  static const ListeningStatsRangeEnum n30d = _$listeningStatsRangeEnum_n30d;
  /// The range that was aggregated.
  @BuiltValueEnumConst(wireName: r'90d')
  static const ListeningStatsRangeEnum n90d = _$listeningStatsRangeEnum_n90d;
  /// The range that was aggregated.
  @BuiltValueEnumConst(wireName: r'365d')
  static const ListeningStatsRangeEnum n365d = _$listeningStatsRangeEnum_n365d;
  /// The range that was aggregated.
  @BuiltValueEnumConst(wireName: r'all')
  static const ListeningStatsRangeEnum all = _$listeningStatsRangeEnum_all;
  /// The range that was aggregated.
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const ListeningStatsRangeEnum unknownDefaultOpenApi = _$listeningStatsRangeEnum_unknownDefaultOpenApi;

  static Serializer<ListeningStatsRangeEnum> get serializer => _$listeningStatsRangeEnumSerializer;

  const ListeningStatsRangeEnum._(String name): super(name);

  static BuiltSet<ListeningStatsRangeEnum> get values => _$listeningStatsRangeEnumValues;
  static ListeningStatsRangeEnum valueOf(String name) => _$listeningStatsRangeEnumValueOf(name);
}

class ListeningStatsBucketEnum extends EnumClass {

  /// The bucket size used.
  @BuiltValueEnumConst(wireName: r'day')
  static const ListeningStatsBucketEnum day = _$listeningStatsBucketEnum_day;
  /// The bucket size used.
  @BuiltValueEnumConst(wireName: r'week')
  static const ListeningStatsBucketEnum week = _$listeningStatsBucketEnum_week;
  /// The bucket size used.
  @BuiltValueEnumConst(wireName: r'month')
  static const ListeningStatsBucketEnum month = _$listeningStatsBucketEnum_month;
  /// The bucket size used.
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const ListeningStatsBucketEnum unknownDefaultOpenApi = _$listeningStatsBucketEnum_unknownDefaultOpenApi;

  static Serializer<ListeningStatsBucketEnum> get serializer => _$listeningStatsBucketEnumSerializer;

  const ListeningStatsBucketEnum._(String name): super(name);

  static BuiltSet<ListeningStatsBucketEnum> get values => _$listeningStatsBucketEnumValues;
  static ListeningStatsBucketEnum valueOf(String name) => _$listeningStatsBucketEnumValueOf(name);
}

