//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'job.g.dart';

/// A server-run catalog job.
///
/// Properties:
/// * [pid] - Job PID.
/// * [kind] - What the job does (`scan`, `analyze`, `enrich`, `organize`).
/// * [state] - Job lifecycle state. Currently `running`, `done`, `failed`, `crashed`, or `canceled`; new states may appear, and clients must treat unknown values as \"not finished successfully yet\" rather than failing. 
/// * [progress] - Completion fraction in [0, 1]. Absent when the job has not yet reported progress or cannot estimate it. 
/// * [message] - Human-readable progress note.
/// * [error] - Failure detail for `failed`/`crashed` jobs.
@BuiltValue()
abstract class Job implements Built<Job, JobBuilder> {
  /// Job PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// What the job does (`scan`, `analyze`, `enrich`, `organize`).
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// Job lifecycle state. Currently `running`, `done`, `failed`, `crashed`, or `canceled`; new states may appear, and clients must treat unknown values as \"not finished successfully yet\" rather than failing. 
  @BuiltValueField(wireName: r'state')
  String get state;

  /// Completion fraction in [0, 1]. Absent when the job has not yet reported progress or cannot estimate it. 
  @BuiltValueField(wireName: r'progress')
  double? get progress;

  /// Human-readable progress note.
  @BuiltValueField(wireName: r'message')
  String? get message;

  /// Failure detail for `failed`/`crashed` jobs.
  @BuiltValueField(wireName: r'error')
  String? get error;

  Job._();

  factory Job([void updates(JobBuilder b)]) = _$Job;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(JobBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Job> get serializer => _$JobSerializer();
}

class _$JobSerializer implements PrimitiveSerializer<Job> {
  @override
  final Iterable<Type> types = const [Job, _$Job];

  @override
  final String wireName = r'Job';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Job object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    yield r'state';
    yield serializers.serialize(
      object.state,
      specifiedType: const FullType(String),
    );
    if (object.progress != null) {
      yield r'progress';
      yield serializers.serialize(
        object.progress,
        specifiedType: const FullType(double),
      );
    }
    if (object.message != null) {
      yield r'message';
      yield serializers.serialize(
        object.message,
        specifiedType: const FullType(String),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Job object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required JobBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.state = valueDes;
          break;
        case r'progress':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.progress = valueDes;
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Job deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = JobBuilder();
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

