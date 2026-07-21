//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_fix_result.g.dart';

/// How much fix work was queued.
///
/// Properties:
/// * [queued] - Items queued for fixing.
@BuiltValue()
abstract class HealthFixResult implements Built<HealthFixResult, HealthFixResultBuilder> {
  /// Items queued for fixing.
  @BuiltValueField(wireName: r'queued')
  int get queued;

  HealthFixResult._();

  factory HealthFixResult([void updates(HealthFixResultBuilder b)]) = _$HealthFixResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthFixResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthFixResult> get serializer => _$HealthFixResultSerializer();
}

class _$HealthFixResultSerializer implements PrimitiveSerializer<HealthFixResult> {
  @override
  final Iterable<Type> types = const [HealthFixResult, _$HealthFixResult];

  @override
  final String wireName = r'HealthFixResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthFixResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'queued';
    yield serializers.serialize(
      object.queued,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    HealthFixResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HealthFixResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'queued':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.queued = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HealthFixResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthFixResultBuilder();
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

