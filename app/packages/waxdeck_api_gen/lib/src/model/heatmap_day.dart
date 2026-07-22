//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'heatmap_day.g.dart';

/// One day's listening.
///
/// Properties:
/// * [date] - The calendar day in the caller's timezone.
/// * [ms] - Milliseconds listened that day.
/// * [sessions] - Listen sessions that day.
@BuiltValue()
abstract class HeatmapDay implements Built<HeatmapDay, HeatmapDayBuilder> {
  /// The calendar day in the caller's timezone.
  @BuiltValueField(wireName: r'date')
  Date get date;

  /// Milliseconds listened that day.
  @BuiltValueField(wireName: r'ms')
  int get ms;

  /// Listen sessions that day.
  @BuiltValueField(wireName: r'sessions')
  int get sessions;

  HeatmapDay._();

  factory HeatmapDay([void updates(HeatmapDayBuilder b)]) = _$HeatmapDay;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HeatmapDayBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HeatmapDay> get serializer => _$HeatmapDaySerializer();
}

class _$HeatmapDaySerializer implements PrimitiveSerializer<HeatmapDay> {
  @override
  final Iterable<Type> types = const [HeatmapDay, _$HeatmapDay];

  @override
  final String wireName = r'HeatmapDay';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HeatmapDay object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'date';
    yield serializers.serialize(
      object.date,
      specifiedType: const FullType(Date),
    );
    yield r'ms';
    yield serializers.serialize(
      object.ms,
      specifiedType: const FullType(int),
    );
    yield r'sessions';
    yield serializers.serialize(
      object.sessions,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    HeatmapDay object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HeatmapDayBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.date = valueDes;
          break;
        case r'ms':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.ms = valueDes;
          break;
        case r'sessions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sessions = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HeatmapDay deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HeatmapDayBuilder();
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

