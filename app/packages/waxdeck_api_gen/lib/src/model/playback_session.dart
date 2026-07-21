//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/playback_session_entry.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playback_session.g.dart';

/// One playback session: a queue playing (or paused) on an endpoint. `positionMs` is the position that was true at `positionAt` (server clock); while `playing`, controllers extrapolate forward with `rate`. `authority` says who advances playback: `remote` sessions are driven by the server (cast, DLNA, jukebox), `mirror` sessions are driven by the playing client and mirrored here. Both are controlled the same way. 
///
/// Properties:
/// * [id] - Session PID. Stable across transfers between endpoints. 
/// * [endpointId] - The endpoint the session plays on.
/// * [endpointName] - The endpoint's display name, for one-call rendering.
/// * [mine] - True when the caller owns the session.
/// * [ownerName] - The owning user's display name. Present on sessions the caller does not own (it is how a shared speaker's UI says who is playing). 
/// * [authority] - `remote` or `mirror` (open string).
/// * [playing] - Whether playback is running right now.
/// * [index] - Zero-based index of the current entry.
/// * [positionMs] - Position within the current entry at `positionAt`.
/// * [positionAt] - Server-clock instant `positionMs` was true, millisecond precision. Extrapolate against the WebSocket clock offset. 
/// * [rate] - Playback rate. 1.0 is normal speed.
/// * [volume] - Endpoint volume, 0 to 1. Absent on endpoints without volume control. 
/// * [repeat] - `off`, `all`, or `one` (open string).
/// * [shuffle] - Whether shuffle is on. `entries` always lists the true play order: turning shuffle on reorders the unplayed remainder (and bumps `queueVersion`); turning it off keeps the current order. 
/// * [queueVersion] - The server-owned queue generation, monotone per session id across transfers and authority changes: it bumps whenever the queue (entries or their order) changes. A playing client's reported version is only an edge signal; the published value here is the server's. 
/// * [entries] - The queue, in play order. Always present on the REST endpoints. WebSocket `session` frames carry it on the first frame of a watch and whenever `queueVersion` bumped, and omit it otherwise (absent means unchanged since the version you last saw; refetch the session if you lost track). 
/// * [ended] - Present true only over the WebSocket, and terminal for that delivery context: the watched or reported session ended, or left the receiver's visibility (a transfer to a private endpoint). Re-list `/player/sessions` to learn which. Never true from the REST endpoints, which answer `not-found` for sessions the caller cannot see. 
/// * [updatedAt] - Last state change (position ticks included).
@BuiltValue()
abstract class PlaybackSession implements Built<PlaybackSession, PlaybackSessionBuilder> {
  /// Session PID. Stable across transfers between endpoints. 
  @BuiltValueField(wireName: r'id')
  String get id;

  /// The endpoint the session plays on.
  @BuiltValueField(wireName: r'endpointId')
  String get endpointId;

  /// The endpoint's display name, for one-call rendering.
  @BuiltValueField(wireName: r'endpointName')
  String? get endpointName;

  /// True when the caller owns the session.
  @BuiltValueField(wireName: r'mine')
  bool get mine;

  /// The owning user's display name. Present on sessions the caller does not own (it is how a shared speaker's UI says who is playing). 
  @BuiltValueField(wireName: r'ownerName')
  String? get ownerName;

  /// `remote` or `mirror` (open string).
  @BuiltValueField(wireName: r'authority')
  String get authority;

  /// Whether playback is running right now.
  @BuiltValueField(wireName: r'playing')
  bool get playing;

  /// Zero-based index of the current entry.
  @BuiltValueField(wireName: r'index')
  int get index;

  /// Position within the current entry at `positionAt`.
  @BuiltValueField(wireName: r'positionMs')
  int get positionMs;

  /// Server-clock instant `positionMs` was true, millisecond precision. Extrapolate against the WebSocket clock offset. 
  @BuiltValueField(wireName: r'positionAt')
  DateTime get positionAt;

  /// Playback rate. 1.0 is normal speed.
  @BuiltValueField(wireName: r'rate')
  double get rate;

  /// Endpoint volume, 0 to 1. Absent on endpoints without volume control. 
  @BuiltValueField(wireName: r'volume')
  double? get volume;

  /// `off`, `all`, or `one` (open string).
  @BuiltValueField(wireName: r'repeat')
  String? get repeat;

  /// Whether shuffle is on. `entries` always lists the true play order: turning shuffle on reorders the unplayed remainder (and bumps `queueVersion`); turning it off keeps the current order. 
  @BuiltValueField(wireName: r'shuffle')
  bool? get shuffle;

  /// The server-owned queue generation, monotone per session id across transfers and authority changes: it bumps whenever the queue (entries or their order) changes. A playing client's reported version is only an edge signal; the published value here is the server's. 
  @BuiltValueField(wireName: r'queueVersion')
  int get queueVersion;

  /// The queue, in play order. Always present on the REST endpoints. WebSocket `session` frames carry it on the first frame of a watch and whenever `queueVersion` bumped, and omit it otherwise (absent means unchanged since the version you last saw; refetch the session if you lost track). 
  @BuiltValueField(wireName: r'entries')
  BuiltList<PlaybackSessionEntry>? get entries;

  /// Present true only over the WebSocket, and terminal for that delivery context: the watched or reported session ended, or left the receiver's visibility (a transfer to a private endpoint). Re-list `/player/sessions` to learn which. Never true from the REST endpoints, which answer `not-found` for sessions the caller cannot see. 
  @BuiltValueField(wireName: r'ended')
  bool? get ended;

  /// Last state change (position ticks included).
  @BuiltValueField(wireName: r'updatedAt')
  DateTime get updatedAt;

  PlaybackSession._();

  factory PlaybackSession([void updates(PlaybackSessionBuilder b)]) = _$PlaybackSession;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaybackSessionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaybackSession> get serializer => _$PlaybackSessionSerializer();
}

class _$PlaybackSessionSerializer implements PrimitiveSerializer<PlaybackSession> {
  @override
  final Iterable<Type> types = const [PlaybackSession, _$PlaybackSession];

  @override
  final String wireName = r'PlaybackSession';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaybackSession object, {
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
    yield r'mine';
    yield serializers.serialize(
      object.mine,
      specifiedType: const FullType(bool),
    );
    if (object.ownerName != null) {
      yield r'ownerName';
      yield serializers.serialize(
        object.ownerName,
        specifiedType: const FullType(String),
      );
    }
    yield r'authority';
    yield serializers.serialize(
      object.authority,
      specifiedType: const FullType(String),
    );
    yield r'playing';
    yield serializers.serialize(
      object.playing,
      specifiedType: const FullType(bool),
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
    if (object.volume != null) {
      yield r'volume';
      yield serializers.serialize(
        object.volume,
        specifiedType: const FullType(double),
      );
    }
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
    yield r'queueVersion';
    yield serializers.serialize(
      object.queueVersion,
      specifiedType: const FullType(int),
    );
    if (object.entries != null) {
      yield r'entries';
      yield serializers.serialize(
        object.entries,
        specifiedType: const FullType(BuiltList, [FullType(PlaybackSessionEntry)]),
      );
    }
    if (object.ended != null) {
      yield r'ended';
      yield serializers.serialize(
        object.ended,
        specifiedType: const FullType(bool),
      );
    }
    yield r'updatedAt';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaybackSession object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaybackSessionBuilder result,
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
        case r'mine':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.mine = valueDes;
          break;
        case r'ownerName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.ownerName = valueDes;
          break;
        case r'authority':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.authority = valueDes;
          break;
        case r'playing':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.playing = valueDes;
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
        case r'volume':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.volume = valueDes;
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
        case r'queueVersion':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.queueVersion = valueDes;
          break;
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlaybackSessionEntry)]),
          ) as BuiltList<PlaybackSessionEntry>;
          result.entries.replace(valueDes);
          break;
        case r'ended':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.ended = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaybackSession deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaybackSessionBuilder();
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

