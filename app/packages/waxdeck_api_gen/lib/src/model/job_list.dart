//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/job.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'job_list.g.dart';

/// Recent catalog jobs.
///
/// Properties:
/// * [jobs] - Jobs, newest first.
@BuiltValue()
abstract class JobList implements Built<JobList, JobListBuilder> {
  /// Jobs, newest first.
  @BuiltValueField(wireName: r'jobs')
  BuiltList<Job> get jobs;

  JobList._();

  factory JobList([void updates(JobListBuilder b)]) = _$JobList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(JobListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<JobList> get serializer => _$JobListSerializer();
}

class _$JobListSerializer implements PrimitiveSerializer<JobList> {
  @override
  final Iterable<Type> types = const [JobList, _$JobList];

  @override
  final String wireName = r'JobList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    JobList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'jobs';
    yield serializers.serialize(
      object.jobs,
      specifiedType: const FullType(BuiltList, [FullType(Job)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    JobList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required JobListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'jobs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Job)]),
          ) as BuiltList<Job>;
          result.jobs.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  JobList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = JobListBuilder();
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

