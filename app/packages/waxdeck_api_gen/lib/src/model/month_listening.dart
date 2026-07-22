//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'month_listening.g.dart';

/// One month's listening.
///
/// Properties:
/// * [month] - Calendar month, 1 is January.
/// * [ms] - Milliseconds listened that month.
/// * [sessions] - Listen sessions that month.
@BuiltValue()
abstract class MonthListening implements Built<MonthListening, MonthListeningBuilder> {
  /// Calendar month, 1 is January.
  @BuiltValueField(wireName: r'month')
  int get month;

  /// Milliseconds listened that month.
  @BuiltValueField(wireName: r'ms')
  int get ms;

  /// Listen sessions that month.
  @BuiltValueField(wireName: r'sessions')
  int get sessions;

  MonthListening._();

  factory MonthListening([void updates(MonthListeningBuilder b)]) = _$MonthListening;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MonthListeningBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MonthListening> get serializer => _$MonthListeningSerializer();
}

class _$MonthListeningSerializer implements PrimitiveSerializer<MonthListening> {
  @override
  final Iterable<Type> types = const [MonthListening, _$MonthListening];

  @override
  final String wireName = r'MonthListening';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MonthListening object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'month';
    yield serializers.serialize(
      object.month,
      specifiedType: const FullType(int),
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
    MonthListening object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MonthListeningBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'month':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.month = valueDes;
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
  MonthListening deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MonthListeningBuilder();
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

