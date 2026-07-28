//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/playback_session_history_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playback_session_history_list.g.dart';

/// The caller's ended sessions, most recently ended first.
///
/// Properties:
/// * [sessions] 
@BuiltValue()
abstract class PlaybackSessionHistoryList implements Built<PlaybackSessionHistoryList, PlaybackSessionHistoryListBuilder> {
  @BuiltValueField(wireName: r'sessions')
  BuiltList<PlaybackSessionHistoryEntry> get sessions;

  PlaybackSessionHistoryList._();

  factory PlaybackSessionHistoryList([void updates(PlaybackSessionHistoryListBuilder b)]) = _$PlaybackSessionHistoryList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaybackSessionHistoryListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaybackSessionHistoryList> get serializer => _$PlaybackSessionHistoryListSerializer();
}

class _$PlaybackSessionHistoryListSerializer implements PrimitiveSerializer<PlaybackSessionHistoryList> {
  @override
  final Iterable<Type> types = const [PlaybackSessionHistoryList, _$PlaybackSessionHistoryList];

  @override
  final String wireName = r'PlaybackSessionHistoryList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaybackSessionHistoryList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sessions';
    yield serializers.serialize(
      object.sessions,
      specifiedType: const FullType(BuiltList, [FullType(PlaybackSessionHistoryEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaybackSessionHistoryList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaybackSessionHistoryListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sessions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlaybackSessionHistoryEntry)]),
          ) as BuiltList<PlaybackSessionHistoryEntry>;
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
  PlaybackSessionHistoryList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaybackSessionHistoryListBuilder();
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

