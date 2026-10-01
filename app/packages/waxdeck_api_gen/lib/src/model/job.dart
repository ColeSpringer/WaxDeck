//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/job_target.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'job.g.dart';

/// A server-run catalog job.
///
/// Properties:
/// * [pid] - Job PID.
/// * [kind] - What the job does: `scan`, `analyze`, `enrich`, `organize`, `import`, `delete`, `restore`, `empty-trash`, or `purge-trash`. New kinds may appear. 
/// * [state] - Job lifecycle state. Currently `running`, `done`, `failed`, `crashed`, or `canceled`; new states may appear, and clients must treat unknown values as \"not finished successfully yet\" rather than failing. 
/// * [progress] - Completion fraction in [0, 1]. Absent when the job has not yet reported progress or cannot estimate it. 
/// * [message] - Human-readable progress note.
/// * [error] - Failure detail for `failed`/`crashed` jobs.
/// * [startedAt] - When the job started.
/// * [finishedAt] - When the job reached a terminal state; absent while running.
/// * [result] - What a finished job did, once it records a summary: a `scan` reports `filesSeen`, `created`, `updated`, `relinked`, `unchanged`, `missing`, `skipped` and `errored` (files); an `analyze` pass `analyzed`, `loudnessMeasured`, `measureFailed`, `skipped` and `errored`; an `enrich` pass the same tallies as the enrichment status's `lastRun`; an `organize` run `profile`, `moved`, `skipped`, `errored` and `sidecarsMoved`. Absent while running and for kinds that record none. Shapes may grow fields. 
/// * [target] 
@BuiltValue()
abstract class Job implements Built<Job, JobBuilder> {
  /// Job PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// What the job does: `scan`, `analyze`, `enrich`, `organize`, `import`, `delete`, `restore`, `empty-trash`, or `purge-trash`. New kinds may appear. 
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

  /// When the job started.
  @BuiltValueField(wireName: r'startedAt')
  DateTime? get startedAt;

  /// When the job reached a terminal state; absent while running.
  @BuiltValueField(wireName: r'finishedAt')
  DateTime? get finishedAt;

  /// What a finished job did, once it records a summary: a `scan` reports `filesSeen`, `created`, `updated`, `relinked`, `unchanged`, `missing`, `skipped` and `errored` (files); an `analyze` pass `analyzed`, `loudnessMeasured`, `measureFailed`, `skipped` and `errored`; an `enrich` pass the same tallies as the enrichment status's `lastRun`; an `organize` run `profile`, `moved`, `skipped`, `errored` and `sidecarsMoved`. Absent while running and for kinds that record none. Shapes may grow fields. 
  @BuiltValueField(wireName: r'result')
  BuiltMap<String, JsonObject?>? get result;

  @BuiltValueField(wireName: r'target')
  JobTarget? get target;

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
    if (object.startedAt != null) {
      yield r'startedAt';
      yield serializers.serialize(
        object.startedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.finishedAt != null) {
      yield r'finishedAt';
      yield serializers.serialize(
        object.finishedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.result != null) {
      yield r'result';
      yield serializers.serialize(
        object.result,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
      );
    }
    if (object.target != null) {
      yield r'target';
      yield serializers.serialize(
        object.target,
        specifiedType: const FullType(JobTarget),
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
            specifiedType: const FullType.nullable(double),
          ) as double?;
          if (valueDes == null) continue;
          result.progress = valueDes;
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.message = valueDes;
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.error = valueDes;
          break;
        case r'startedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.startedAt = valueDes;
          break;
        case r'finishedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.finishedAt = valueDes;
          break;
        case r'result':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
          ) as BuiltMap<String, JsonObject?>?;
          if (valueDes == null) continue;
          result.result.replace(valueDes);
          break;
        case r'target':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(JobTarget),
          ) as JobTarget?;
          if (valueDes == null) continue;
          result.target.replace(valueDes);
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


