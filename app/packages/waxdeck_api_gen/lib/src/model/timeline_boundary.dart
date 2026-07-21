//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'timeline_boundary.g.dart';

/// One queue item's place on the combined timeline. Offsets and durations are in samples at the timeline's `envelopeRate`. Without crossfade, members tile exactly; with crossfade, consecutive members overlap, so map positions by offset, never by summing durations. 
///
/// Properties:
/// * [pid] - The queue item this boundary describes.
/// * [offsetSamples] - Where this member starts on the timeline.
/// * [durationSamples] - The member's own length on the timeline.
@BuiltValue()
abstract class TimelineBoundary implements Built<TimelineBoundary, TimelineBoundaryBuilder> {
  /// The queue item this boundary describes.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Where this member starts on the timeline.
  @BuiltValueField(wireName: r'offsetSamples')
  int get offsetSamples;

  /// The member's own length on the timeline.
  @BuiltValueField(wireName: r'durationSamples')
  int get durationSamples;

  TimelineBoundary._();

  factory TimelineBoundary([void updates(TimelineBoundaryBuilder b)]) = _$TimelineBoundary;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TimelineBoundaryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TimelineBoundary> get serializer => _$TimelineBoundarySerializer();
}

class _$TimelineBoundarySerializer implements PrimitiveSerializer<TimelineBoundary> {
  @override
  final Iterable<Type> types = const [TimelineBoundary, _$TimelineBoundary];

  @override
  final String wireName = r'TimelineBoundary';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TimelineBoundary object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'offsetSamples';
    yield serializers.serialize(
      object.offsetSamples,
      specifiedType: const FullType(int),
    );
    yield r'durationSamples';
    yield serializers.serialize(
      object.durationSamples,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TimelineBoundary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TimelineBoundaryBuilder result,
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
        case r'offsetSamples':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.offsetSamples = valueDes;
          break;
        case r'durationSamples':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationSamples = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TimelineBoundary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TimelineBoundaryBuilder();
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

