//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_fix_result.g.dart';

/// The fix that started: exactly one of `jobPid` and `taskId` names where it can be followed. 
///
/// Properties:
/// * [queued] - Items the fix set out to reach.
/// * [jobPid] - The catalog enrichment job running the fix, for an unscoped fix of an enrichment-backed rule. 
/// * [taskId] - The `health-fix` tool task running the fix, otherwise.
@BuiltValue()
abstract class HealthFixResult implements Built<HealthFixResult, HealthFixResultBuilder> {
  /// Items the fix set out to reach.
  @BuiltValueField(wireName: r'queued')
  int get queued;

  /// The catalog enrichment job running the fix, for an unscoped fix of an enrichment-backed rule. 
  @BuiltValueField(wireName: r'jobPid')
  String? get jobPid;

  /// The `health-fix` tool task running the fix, otherwise.
  @BuiltValueField(wireName: r'taskId')
  String? get taskId;

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
    if (object.jobPid != null) {
      yield r'jobPid';
      yield serializers.serialize(
        object.jobPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.taskId != null) {
      yield r'taskId';
      yield serializers.serialize(
        object.taskId,
        specifiedType: const FullType(String),
      );
    }
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
        case r'jobPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.jobPid = valueDes;
          break;
        case r'taskId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.taskId = valueDes;
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


