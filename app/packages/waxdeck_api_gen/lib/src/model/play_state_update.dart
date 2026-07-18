//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'play_state_update.g.dart';

/// A resume-position checkpoint.
///
/// Properties:
/// * [positionMs] - Playback position in milliseconds.
/// * [recordedAt] - When the checkpoint was recorded on the client, sent only when replaying an offline queue. The server reconciles replays per medium: audiobooks and long tracks are recency-primary (the most recently recorded position wins, so a stale replay never drags a 14-hour book backward or forward), while music and podcast episodes are furthest-position-wins with a recency guard (the further position wins unless the nearer one is substantially more recent, honoring a deliberate rewind). Future-dated values are clamped to the server clock. Live checkpoints omit it and always apply. The response does not reveal whether a replay was applied or skipped: after flushing an offline queue, clients learn the winning state through `/sync/server` (a skipped replay means the winner is already in the event stream). 
@BuiltValue()
abstract class PlayStateUpdate implements Built<PlayStateUpdate, PlayStateUpdateBuilder> {
  /// Playback position in milliseconds.
  @BuiltValueField(wireName: r'positionMs')
  int get positionMs;

  /// When the checkpoint was recorded on the client, sent only when replaying an offline queue. The server reconciles replays per medium: audiobooks and long tracks are recency-primary (the most recently recorded position wins, so a stale replay never drags a 14-hour book backward or forward), while music and podcast episodes are furthest-position-wins with a recency guard (the further position wins unless the nearer one is substantially more recent, honoring a deliberate rewind). Future-dated values are clamped to the server clock. Live checkpoints omit it and always apply. The response does not reveal whether a replay was applied or skipped: after flushing an offline queue, clients learn the winning state through `/sync/server` (a skipped replay means the winner is already in the event stream). 
  @BuiltValueField(wireName: r'recordedAt')
  DateTime? get recordedAt;

  PlayStateUpdate._();

  factory PlayStateUpdate([void updates(PlayStateUpdateBuilder b)]) = _$PlayStateUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlayStateUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlayStateUpdate> get serializer => _$PlayStateUpdateSerializer();
}

class _$PlayStateUpdateSerializer implements PrimitiveSerializer<PlayStateUpdate> {
  @override
  final Iterable<Type> types = const [PlayStateUpdate, _$PlayStateUpdate];

  @override
  final String wireName = r'PlayStateUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlayStateUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'positionMs';
    yield serializers.serialize(
      object.positionMs,
      specifiedType: const FullType(int),
    );
    if (object.recordedAt != null) {
      yield r'recordedAt';
      yield serializers.serialize(
        object.recordedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlayStateUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlayStateUpdateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'positionMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.positionMs = valueDes;
          break;
        case r'recordedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.recordedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlayStateUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlayStateUpdateBuilder();
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

