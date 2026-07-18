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
@BuiltValue()
abstract class PlayStateUpdate implements Built<PlayStateUpdate, PlayStateUpdateBuilder> {
  /// Playback position in milliseconds.
  @BuiltValueField(wireName: r'positionMs')
  int get positionMs;

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

