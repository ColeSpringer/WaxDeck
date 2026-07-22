//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'listening_bucket.g.dart';

/// One chart bucket.
///
/// Properties:
/// * [start] - First calendar day of the bucket in the caller's timezone. 
/// * [ms] - Milliseconds listened in the bucket.
/// * [sessions] - Listen sessions in the bucket.
@BuiltValue()
abstract class ListeningBucket implements Built<ListeningBucket, ListeningBucketBuilder> {
  /// First calendar day of the bucket in the caller's timezone. 
  @BuiltValueField(wireName: r'start')
  Date get start;

  /// Milliseconds listened in the bucket.
  @BuiltValueField(wireName: r'ms')
  int get ms;

  /// Listen sessions in the bucket.
  @BuiltValueField(wireName: r'sessions')
  int get sessions;

  ListeningBucket._();

  factory ListeningBucket([void updates(ListeningBucketBuilder b)]) = _$ListeningBucket;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListeningBucketBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListeningBucket> get serializer => _$ListeningBucketSerializer();
}

class _$ListeningBucketSerializer implements PrimitiveSerializer<ListeningBucket> {
  @override
  final Iterable<Type> types = const [ListeningBucket, _$ListeningBucket];

  @override
  final String wireName = r'ListeningBucket';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListeningBucket object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'start';
    yield serializers.serialize(
      object.start,
      specifiedType: const FullType(Date),
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
    ListeningBucket object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListeningBucketBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'start':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.start = valueDes;
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
  ListeningBucket deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListeningBucketBuilder();
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

