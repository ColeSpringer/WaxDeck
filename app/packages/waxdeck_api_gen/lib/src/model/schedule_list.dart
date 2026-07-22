//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/schedule.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'schedule_list.g.dart';

/// Every schedule.
///
/// Properties:
/// * [schedules] - One entry per kind.
@BuiltValue()
abstract class ScheduleList implements Built<ScheduleList, ScheduleListBuilder> {
  /// One entry per kind.
  @BuiltValueField(wireName: r'schedules')
  BuiltList<Schedule> get schedules;

  ScheduleList._();

  factory ScheduleList([void updates(ScheduleListBuilder b)]) = _$ScheduleList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ScheduleListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ScheduleList> get serializer => _$ScheduleListSerializer();
}

class _$ScheduleListSerializer implements PrimitiveSerializer<ScheduleList> {
  @override
  final Iterable<Type> types = const [ScheduleList, _$ScheduleList];

  @override
  final String wireName = r'ScheduleList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ScheduleList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'schedules';
    yield serializers.serialize(
      object.schedules,
      specifiedType: const FullType(BuiltList, [FullType(Schedule)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ScheduleList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ScheduleListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'schedules':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Schedule)]),
          ) as BuiltList<Schedule>;
          result.schedules.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ScheduleList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ScheduleListBuilder();
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

