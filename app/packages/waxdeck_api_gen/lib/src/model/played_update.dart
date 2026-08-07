//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'played_update.g.dart';

/// A direct change to an item's played and finished flags.
///
/// Properties:
/// * [played] - Whether the item counts as played at least once.
/// * [finished] - Whether the listener reached the end. Never true while `played` is false. 
/// * [playCount] - The play count to store. Omitted or null keeps the stored count, which is what a client that only means to flip the flags should send; 0 resets it, so an undo of a mis-tapped mark clears the play it added rather than leaving it counted. Setting `played` true without naming a count stores the smallest count consistent with it, so a played item never sorts as never-played. 
/// * [recordedAt] - When the change was made on the client, sent only when replaying an offline queue. The server skips the write when the item's flags changed more recently than this. Live mutations omit it and always apply, which is what an interactive un-mark wants: a client clock trailing the server would otherwise drop it as stale. 
@BuiltValue()
abstract class PlayedUpdate implements Built<PlayedUpdate, PlayedUpdateBuilder> {
  /// Whether the item counts as played at least once.
  @BuiltValueField(wireName: r'played')
  bool get played;

  /// Whether the listener reached the end. Never true while `played` is false. 
  @BuiltValueField(wireName: r'finished')
  bool get finished;

  /// The play count to store. Omitted or null keeps the stored count, which is what a client that only means to flip the flags should send; 0 resets it, so an undo of a mis-tapped mark clears the play it added rather than leaving it counted. Setting `played` true without naming a count stores the smallest count consistent with it, so a played item never sorts as never-played. 
  @BuiltValueField(wireName: r'playCount')
  int? get playCount;

  /// When the change was made on the client, sent only when replaying an offline queue. The server skips the write when the item's flags changed more recently than this. Live mutations omit it and always apply, which is what an interactive un-mark wants: a client clock trailing the server would otherwise drop it as stale. 
  @BuiltValueField(wireName: r'recordedAt')
  DateTime? get recordedAt;

  PlayedUpdate._();

  factory PlayedUpdate([void updates(PlayedUpdateBuilder b)]) = _$PlayedUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlayedUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlayedUpdate> get serializer => _$PlayedUpdateSerializer();
}

class _$PlayedUpdateSerializer implements PrimitiveSerializer<PlayedUpdate> {
  @override
  final Iterable<Type> types = const [PlayedUpdate, _$PlayedUpdate];

  @override
  final String wireName = r'PlayedUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlayedUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'played';
    yield serializers.serialize(
      object.played,
      specifiedType: const FullType(bool),
    );
    yield r'finished';
    yield serializers.serialize(
      object.finished,
      specifiedType: const FullType(bool),
    );
    if (object.playCount != null) {
      yield r'playCount';
      yield serializers.serialize(
        object.playCount,
        specifiedType: const FullType.nullable(int),
      );
    }
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
    PlayedUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlayedUpdateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'played':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.played = valueDes;
          break;
        case r'finished':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.finished = valueDes;
          break;
        case r'playCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.playCount = valueDes;
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
  PlayedUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlayedUpdateBuilder();
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

