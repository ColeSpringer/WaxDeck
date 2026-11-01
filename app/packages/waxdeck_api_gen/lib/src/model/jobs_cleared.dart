//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'jobs_cleared.g.dart';

/// The result of clearing finished catalog jobs.
///
/// Properties:
/// * [cleared] - How many ended jobs the caller's list held before it was cleared: every one `GET /jobs` would list, whether or not a page of it reached them. 
@BuiltValue()
abstract class JobsCleared implements Built<JobsCleared, JobsClearedBuilder> {
  /// How many ended jobs the caller's list held before it was cleared: every one `GET /jobs` would list, whether or not a page of it reached them. 
  @BuiltValueField(wireName: r'cleared')
  int get cleared;

  JobsCleared._();

  factory JobsCleared([void updates(JobsClearedBuilder b)]) = _$JobsCleared;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(JobsClearedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<JobsCleared> get serializer => _$JobsClearedSerializer();
}

class _$JobsClearedSerializer implements PrimitiveSerializer<JobsCleared> {
  @override
  final Iterable<Type> types = const [JobsCleared, _$JobsCleared];

  @override
  final String wireName = r'JobsCleared';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    JobsCleared object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'cleared';
    yield serializers.serialize(
      object.cleared,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    JobsCleared object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required JobsClearedBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'cleared':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.cleared = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  JobsCleared deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = JobsClearedBuilder();
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


