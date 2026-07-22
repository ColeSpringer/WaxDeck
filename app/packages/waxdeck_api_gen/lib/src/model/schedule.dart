//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/schedule_kind.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'schedule.g.dart';

/// One scheduled job's configuration and history.
///
/// Properties:
/// * [kind] 
/// * [cron] - Five-field cron expression (minute, hour, day of month, month, day of week), server-local time. 
/// * [enabled] - Whether the schedule fires.
/// * [lastRunAt] - When the job last ran; absent if never.
/// * [lastStatus] - `ok` or `failed` for the last run. An open string.
/// * [lastError] - Failure detail when the last run failed.
/// * [nextRunAt] - The next firing time while enabled.
@BuiltValue()
abstract class Schedule implements Built<Schedule, ScheduleBuilder> {
  @BuiltValueField(wireName: r'kind')
  ScheduleKind get kind;
  // enum kindEnum {  scan,  backup,  prune,  };

  /// Five-field cron expression (minute, hour, day of month, month, day of week), server-local time. 
  @BuiltValueField(wireName: r'cron')
  String get cron;

  /// Whether the schedule fires.
  @BuiltValueField(wireName: r'enabled')
  bool get enabled;

  /// When the job last ran; absent if never.
  @BuiltValueField(wireName: r'lastRunAt')
  DateTime? get lastRunAt;

  /// `ok` or `failed` for the last run. An open string.
  @BuiltValueField(wireName: r'lastStatus')
  String? get lastStatus;

  /// Failure detail when the last run failed.
  @BuiltValueField(wireName: r'lastError')
  String? get lastError;

  /// The next firing time while enabled.
  @BuiltValueField(wireName: r'nextRunAt')
  DateTime? get nextRunAt;

  Schedule._();

  factory Schedule([void updates(ScheduleBuilder b)]) = _$Schedule;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ScheduleBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Schedule> get serializer => _$ScheduleSerializer();
}

class _$ScheduleSerializer implements PrimitiveSerializer<Schedule> {
  @override
  final Iterable<Type> types = const [Schedule, _$Schedule];

  @override
  final String wireName = r'Schedule';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Schedule object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(ScheduleKind),
    );
    yield r'cron';
    yield serializers.serialize(
      object.cron,
      specifiedType: const FullType(String),
    );
    yield r'enabled';
    yield serializers.serialize(
      object.enabled,
      specifiedType: const FullType(bool),
    );
    if (object.lastRunAt != null) {
      yield r'lastRunAt';
      yield serializers.serialize(
        object.lastRunAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.lastStatus != null) {
      yield r'lastStatus';
      yield serializers.serialize(
        object.lastStatus,
        specifiedType: const FullType(String),
      );
    }
    if (object.lastError != null) {
      yield r'lastError';
      yield serializers.serialize(
        object.lastError,
        specifiedType: const FullType(String),
      );
    }
    if (object.nextRunAt != null) {
      yield r'nextRunAt';
      yield serializers.serialize(
        object.nextRunAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Schedule object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ScheduleBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ScheduleKind),
          ) as ScheduleKind;
          result.kind = valueDes;
          break;
        case r'cron':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cron = valueDes;
          break;
        case r'enabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.enabled = valueDes;
          break;
        case r'lastRunAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastRunAt = valueDes;
          break;
        case r'lastStatus':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastStatus = valueDes;
          break;
        case r'lastError':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastError = valueDes;
          break;
        case r'nextRunAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.nextRunAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Schedule deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ScheduleBuilder();
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

