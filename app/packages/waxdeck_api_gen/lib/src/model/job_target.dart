//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'job_target.g.dart';

/// What a targeted job ran on; absent for a whole pass. A targeted job is announced only to whoever started it. 
///
/// Properties:
/// * [type] - `item`, `artist`, `release_group`, `album`, `library` or `trash`; new types may appear. 
/// * [pid] - The target's PID.
/// * [name] - The target's name, when it can still be read.
@BuiltValue()
abstract class JobTarget implements Built<JobTarget, JobTargetBuilder> {
  /// `item`, `artist`, `release_group`, `album`, `library` or `trash`; new types may appear. 
  @BuiltValueField(wireName: r'type')
  String get type;

  /// The target's PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// The target's name, when it can still be read.
  @BuiltValueField(wireName: r'name')
  String? get name;

  JobTarget._();

  factory JobTarget([void updates(JobTargetBuilder b)]) = _$JobTarget;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(JobTargetBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<JobTarget> get serializer => _$JobTargetSerializer();
}

class _$JobTargetSerializer implements PrimitiveSerializer<JobTarget> {
  @override
  final Iterable<Type> types = const [JobTarget, _$JobTarget];

  @override
  final String wireName = r'JobTarget';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    JobTarget object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    JobTarget object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required JobTargetBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.type = valueDes;
          break;
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.name = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  JobTarget deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = JobTargetBuilder();
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


