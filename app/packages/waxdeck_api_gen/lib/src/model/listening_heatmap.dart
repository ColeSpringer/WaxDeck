//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/heatmap_day.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'listening_heatmap.g.dart';

/// Per-day listening for one calendar year, plus streaks.
///
/// Properties:
/// * [year] - The calendar year.
/// * [timezone] - IANA timezone the days were bucketed in.
/// * [days] - Days with listening, chronological.
/// * [currentStreakDays] - Consecutive listening days ending today or yesterday, in the caller's timezone. Crosses year boundaries. 0 when the streak is broken. 
/// * [longestStreakDays] - The longest run of consecutive listening days that touches the requested year. Crosses year boundaries. 
@BuiltValue()
abstract class ListeningHeatmap implements Built<ListeningHeatmap, ListeningHeatmapBuilder> {
  /// The calendar year.
  @BuiltValueField(wireName: r'year')
  int get year;

  /// IANA timezone the days were bucketed in.
  @BuiltValueField(wireName: r'timezone')
  String get timezone;

  /// Days with listening, chronological.
  @BuiltValueField(wireName: r'days')
  BuiltList<HeatmapDay> get days;

  /// Consecutive listening days ending today or yesterday, in the caller's timezone. Crosses year boundaries. 0 when the streak is broken. 
  @BuiltValueField(wireName: r'currentStreakDays')
  int get currentStreakDays;

  /// The longest run of consecutive listening days that touches the requested year. Crosses year boundaries. 
  @BuiltValueField(wireName: r'longestStreakDays')
  int get longestStreakDays;

  ListeningHeatmap._();

  factory ListeningHeatmap([void updates(ListeningHeatmapBuilder b)]) = _$ListeningHeatmap;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListeningHeatmapBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListeningHeatmap> get serializer => _$ListeningHeatmapSerializer();
}

class _$ListeningHeatmapSerializer implements PrimitiveSerializer<ListeningHeatmap> {
  @override
  final Iterable<Type> types = const [ListeningHeatmap, _$ListeningHeatmap];

  @override
  final String wireName = r'ListeningHeatmap';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListeningHeatmap object, {
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
    yield r'days';
    yield serializers.serialize(
      object.days,
      specifiedType: const FullType(BuiltList, [FullType(HeatmapDay)]),
    );
    yield r'currentStreakDays';
    yield serializers.serialize(
      object.currentStreakDays,
      specifiedType: const FullType(int),
    );
    yield r'longestStreakDays';
    yield serializers.serialize(
      object.longestStreakDays,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ListeningHeatmap object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListeningHeatmapBuilder result,
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
        case r'days':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(HeatmapDay)]),
          ) as BuiltList<HeatmapDay>;
          result.days.replace(valueDes);
          break;
        case r'currentStreakDays':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.currentStreakDays = valueDes;
          break;
        case r'longestStreakDays':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.longestStreakDays = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ListeningHeatmap deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListeningHeatmapBuilder();
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

