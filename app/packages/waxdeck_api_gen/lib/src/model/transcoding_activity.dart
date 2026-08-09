//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'transcoding_activity.g.dart';

/// What the transcoder is doing right now, for context beside the limits. 
///
/// Properties:
/// * [activeSessions] - Engine-backed streams in flight: what the concurrent caps are counting. Both a floor and a ceiling on what is \"really\" being transcoded - a client that forced the source's own format is routed through the engine and counted here though nothing is re-encoded, and HLS timeline segments are admitted by the streaming engine's own control and are not counted at all. 
@BuiltValue()
abstract class TranscodingActivity implements Built<TranscodingActivity, TranscodingActivityBuilder> {
  /// Engine-backed streams in flight: what the concurrent caps are counting. Both a floor and a ceiling on what is \"really\" being transcoded - a client that forced the source's own format is routed through the engine and counted here though nothing is re-encoded, and HLS timeline segments are admitted by the streaming engine's own control and are not counted at all. 
  @BuiltValueField(wireName: r'activeSessions')
  int get activeSessions;

  TranscodingActivity._();

  factory TranscodingActivity([void updates(TranscodingActivityBuilder b)]) = _$TranscodingActivity;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TranscodingActivityBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TranscodingActivity> get serializer => _$TranscodingActivitySerializer();
}

class _$TranscodingActivitySerializer implements PrimitiveSerializer<TranscodingActivity> {
  @override
  final Iterable<Type> types = const [TranscodingActivity, _$TranscodingActivity];

  @override
  final String wireName = r'TranscodingActivity';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TranscodingActivity object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'activeSessions';
    yield serializers.serialize(
      object.activeSessions,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TranscodingActivity object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TranscodingActivityBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'activeSessions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.activeSessions = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TranscodingActivity deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TranscodingActivityBuilder();
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

