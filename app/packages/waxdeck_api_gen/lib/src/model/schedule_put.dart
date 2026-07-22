//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'schedule_put.g.dart';

/// A schedule change.
///
/// Properties:
/// * [cron] - Five-field cron expression.
/// * [enabled] - Whether the schedule fires.
@BuiltValue()
abstract class SchedulePut implements Built<SchedulePut, SchedulePutBuilder> {
  /// Five-field cron expression.
  @BuiltValueField(wireName: r'cron')
  String get cron;

  /// Whether the schedule fires.
  @BuiltValueField(wireName: r'enabled')
  bool get enabled;

  SchedulePut._();

  factory SchedulePut([void updates(SchedulePutBuilder b)]) = _$SchedulePut;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SchedulePutBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SchedulePut> get serializer => _$SchedulePutSerializer();
}

class _$SchedulePutSerializer implements PrimitiveSerializer<SchedulePut> {
  @override
  final Iterable<Type> types = const [SchedulePut, _$SchedulePut];

  @override
  final String wireName = r'SchedulePut';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SchedulePut object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    SchedulePut object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SchedulePutBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SchedulePut deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SchedulePutBuilder();
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

