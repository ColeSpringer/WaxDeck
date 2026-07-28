//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/playback_session_entry.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playback_session_history_entry.g.dart';

/// One ended playback session, as the state it stopped in. It has no live half: nothing extrapolates, `positionMs` is final, and the session cannot be controlled or resumed in place — restore means starting a new session from this queue, index, and position. Deliberately not a `PlaybackSession` with a flag: a row here is history, while that schema's `ended` marks a live session's last frame, and one type meaning both would make callers ask which transport an object arrived on. 
///
/// Properties:
/// * [id] - The session's PID. It names a session that no longer exists; the id is here to correlate with what the caller may have seen live, not to address anything. 
/// * [endpointId] - The endpoint the session was playing on.
/// * [endpointName] - The endpoint's display name, when it is still known. Absent for an endpoint that has since gone away, which a client endpoint does on every sign-out; render the entry without it rather than treating that as an error. 
/// * [authority] - How the session was driven: `remote` (the server drove a cast, DLNA, or jukebox endpoint) or `mirror` (a client played it and reported here). Open string. 
/// * [index] - Zero-based index of the entry it stopped on.
/// * [positionMs] - Final position within that entry.
/// * [positionAt] - Server-clock instant `positionMs` was true. For a session ended deliberately that is the instant it ended; for one interrupted by a disconnect or a restart it is the last checkpoint before the interruption, a few seconds earlier. This is the sort key: the list is newest first. 
/// * [rate] - The rate it was playing at. 1.0 is normal speed.
/// * [repeat] - `off`, `all`, or `one` (open string).
/// * [shuffle] - Whether shuffle was on. `entries` is the play order as it stood, already shuffled. 
/// * [entries] - The queue as it stood, in play order.
@BuiltValue()
abstract class PlaybackSessionHistoryEntry implements Built<PlaybackSessionHistoryEntry, PlaybackSessionHistoryEntryBuilder> {
  /// The session's PID. It names a session that no longer exists; the id is here to correlate with what the caller may have seen live, not to address anything. 
  @BuiltValueField(wireName: r'id')
  String get id;

  /// The endpoint the session was playing on.
  @BuiltValueField(wireName: r'endpointId')
  String get endpointId;

  /// The endpoint's display name, when it is still known. Absent for an endpoint that has since gone away, which a client endpoint does on every sign-out; render the entry without it rather than treating that as an error. 
  @BuiltValueField(wireName: r'endpointName')
  String? get endpointName;

  /// How the session was driven: `remote` (the server drove a cast, DLNA, or jukebox endpoint) or `mirror` (a client played it and reported here). Open string. 
  @BuiltValueField(wireName: r'authority')
  String get authority;

  /// Zero-based index of the entry it stopped on.
  @BuiltValueField(wireName: r'index')
  int get index;

  /// Final position within that entry.
  @BuiltValueField(wireName: r'positionMs')
  int get positionMs;

  /// Server-clock instant `positionMs` was true. For a session ended deliberately that is the instant it ended; for one interrupted by a disconnect or a restart it is the last checkpoint before the interruption, a few seconds earlier. This is the sort key: the list is newest first. 
  @BuiltValueField(wireName: r'positionAt')
  DateTime get positionAt;

  /// The rate it was playing at. 1.0 is normal speed.
  @BuiltValueField(wireName: r'rate')
  double get rate;

  /// `off`, `all`, or `one` (open string).
  @BuiltValueField(wireName: r'repeat')
  String? get repeat;

  /// Whether shuffle was on. `entries` is the play order as it stood, already shuffled. 
  @BuiltValueField(wireName: r'shuffle')
  bool? get shuffle;

  /// The queue as it stood, in play order.
  @BuiltValueField(wireName: r'entries')
  BuiltList<PlaybackSessionEntry> get entries;

  PlaybackSessionHistoryEntry._();

  factory PlaybackSessionHistoryEntry([void updates(PlaybackSessionHistoryEntryBuilder b)]) = _$PlaybackSessionHistoryEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaybackSessionHistoryEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaybackSessionHistoryEntry> get serializer => _$PlaybackSessionHistoryEntrySerializer();
}

class _$PlaybackSessionHistoryEntrySerializer implements PrimitiveSerializer<PlaybackSessionHistoryEntry> {
  @override
  final Iterable<Type> types = const [PlaybackSessionHistoryEntry, _$PlaybackSessionHistoryEntry];

  @override
  final String wireName = r'PlaybackSessionHistoryEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaybackSessionHistoryEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'endpointId';
    yield serializers.serialize(
      object.endpointId,
      specifiedType: const FullType(String),
    );
    if (object.endpointName != null) {
      yield r'endpointName';
      yield serializers.serialize(
        object.endpointName,
        specifiedType: const FullType(String),
      );
    }
    yield r'authority';
    yield serializers.serialize(
      object.authority,
      specifiedType: const FullType(String),
    );
    yield r'index';
    yield serializers.serialize(
      object.index,
      specifiedType: const FullType(int),
    );
    yield r'positionMs';
    yield serializers.serialize(
      object.positionMs,
      specifiedType: const FullType(int),
    );
    yield r'positionAt';
    yield serializers.serialize(
      object.positionAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'rate';
    yield serializers.serialize(
      object.rate,
      specifiedType: const FullType(double),
    );
    if (object.repeat != null) {
      yield r'repeat';
      yield serializers.serialize(
        object.repeat,
        specifiedType: const FullType(String),
      );
    }
    if (object.shuffle != null) {
      yield r'shuffle';
      yield serializers.serialize(
        object.shuffle,
        specifiedType: const FullType(bool),
      );
    }
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(PlaybackSessionEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaybackSessionHistoryEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaybackSessionHistoryEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'endpointId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.endpointId = valueDes;
          break;
        case r'endpointName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.endpointName = valueDes;
          break;
        case r'authority':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.authority = valueDes;
          break;
        case r'index':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.index = valueDes;
          break;
        case r'positionMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.positionMs = valueDes;
          break;
        case r'positionAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.positionAt = valueDes;
          break;
        case r'rate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.rate = valueDes;
          break;
        case r'repeat':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.repeat = valueDes;
          break;
        case r'shuffle':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.shuffle = valueDes;
          break;
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlaybackSessionEntry)]),
          ) as BuiltList<PlaybackSessionEntry>;
          result.entries.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaybackSessionHistoryEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaybackSessionHistoryEntryBuilder();
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

