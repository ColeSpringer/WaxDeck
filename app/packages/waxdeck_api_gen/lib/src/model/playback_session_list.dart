//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/playback_session.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playback_session_list.g.dart';

/// The sessions visible to the caller, most recent activity first.
///
/// Properties:
/// * [sessions] 
@BuiltValue()
abstract class PlaybackSessionList implements Built<PlaybackSessionList, PlaybackSessionListBuilder> {
  @BuiltValueField(wireName: r'sessions')
  BuiltList<PlaybackSession> get sessions;

  PlaybackSessionList._();

  factory PlaybackSessionList([void updates(PlaybackSessionListBuilder b)]) = _$PlaybackSessionList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaybackSessionListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaybackSessionList> get serializer => _$PlaybackSessionListSerializer();
}

class _$PlaybackSessionListSerializer implements PrimitiveSerializer<PlaybackSessionList> {
  @override
  final Iterable<Type> types = const [PlaybackSessionList, _$PlaybackSessionList];

  @override
  final String wireName = r'PlaybackSessionList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaybackSessionList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sessions';
    yield serializers.serialize(
      object.sessions,
      specifiedType: const FullType(BuiltList, [FullType(PlaybackSession)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaybackSessionList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaybackSessionListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sessions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlaybackSession)]),
          ) as BuiltList<PlaybackSession>;
          result.sessions.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaybackSessionList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaybackSessionListBuilder();
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

