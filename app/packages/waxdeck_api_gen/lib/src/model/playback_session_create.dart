//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playback_session_create.g.dart';

/// Start playback of a queue on an endpoint.
///
/// Properties:
/// * [endpointId] - The target endpoint.
/// * [itemPids] - The queue, in play order.
/// * [index] - Zero-based entry to start at. Defaults to 0.
/// * [positionMs] - Position within the starting entry. Defaults to 0.
/// * [play] - Start playing immediately. Defaults to true; false loads paused. 
/// * [rate] - Playback rate to start at. Defaults to 1.0. A client handing its own playback over carries the rate it was playing at, so a book being read at 1.5x goes on at 1.5x - on a target that has a rate to set. An endpoint reporting `rateControl: false` plays at 1.0 and the session says so, rather than refusing the queue over a mode the room cannot have: `positionMs` is extrapolated with this rate, so recording one the device is not playing at would run every controller's scrubber fast. 
/// * [repeat] - `off`, `all`, or `one` (open string). Defaults to `off`.
/// * [shuffle] - Whether the queue is already shuffled. `itemPids` is the play order either way, so this changes nothing about what plays next; it records what the listener turned on, so a controller draws the mode the queue is in. 
/// * [handoffFrom] - A client endpoint of the caller's whose session this create replaces. One the caller can see that is not a client endpoint of their own answers `forbidden`, because silencing it would be silencing somebody else's device; one they cannot see is nothing to end, and ends nothing. That last case is not a refusal on purpose. The field is for a client whose command bus is down, and a bus that is down is a connection the server has already dropped - which unregisters the endpoint and ends its session. The precondition already holds, so answering `not-found` would refuse to start the queue in the room over work that was already done. For a client that is playing and cannot transfer: the ordinary handoff is `POST /player/sessions/{sessionId}/transfer`, which needs the mirror session's id. A client that never learned one - the command bus was down, its first report went unanswered, the server restarted - creates the session here from its whole local snapshot instead and names itself, so the server can end the session it holds for that endpoint. The client silences itself once this call succeeds rather than waiting for a routed `stop`, which by definition cannot reach it. 
@BuiltValue()
abstract class PlaybackSessionCreate implements Built<PlaybackSessionCreate, PlaybackSessionCreateBuilder> {
  /// The target endpoint.
  @BuiltValueField(wireName: r'endpointId')
  String get endpointId;

  /// The queue, in play order.
  @BuiltValueField(wireName: r'itemPids')
  BuiltList<String> get itemPids;

  /// Zero-based entry to start at. Defaults to 0.
  @BuiltValueField(wireName: r'index')
  int? get index;

  /// Position within the starting entry. Defaults to 0.
  @BuiltValueField(wireName: r'positionMs')
  int? get positionMs;

  /// Start playing immediately. Defaults to true; false loads paused. 
  @BuiltValueField(wireName: r'play')
  bool? get play;

  /// Playback rate to start at. Defaults to 1.0. A client handing its own playback over carries the rate it was playing at, so a book being read at 1.5x goes on at 1.5x - on a target that has a rate to set. An endpoint reporting `rateControl: false` plays at 1.0 and the session says so, rather than refusing the queue over a mode the room cannot have: `positionMs` is extrapolated with this rate, so recording one the device is not playing at would run every controller's scrubber fast. 
  @BuiltValueField(wireName: r'rate')
  double? get rate;

  /// `off`, `all`, or `one` (open string). Defaults to `off`.
  @BuiltValueField(wireName: r'repeat')
  String? get repeat;

  /// Whether the queue is already shuffled. `itemPids` is the play order either way, so this changes nothing about what plays next; it records what the listener turned on, so a controller draws the mode the queue is in. 
  @BuiltValueField(wireName: r'shuffle')
  bool? get shuffle;

  /// A client endpoint of the caller's whose session this create replaces. One the caller can see that is not a client endpoint of their own answers `forbidden`, because silencing it would be silencing somebody else's device; one they cannot see is nothing to end, and ends nothing. That last case is not a refusal on purpose. The field is for a client whose command bus is down, and a bus that is down is a connection the server has already dropped - which unregisters the endpoint and ends its session. The precondition already holds, so answering `not-found` would refuse to start the queue in the room over work that was already done. For a client that is playing and cannot transfer: the ordinary handoff is `POST /player/sessions/{sessionId}/transfer`, which needs the mirror session's id. A client that never learned one - the command bus was down, its first report went unanswered, the server restarted - creates the session here from its whole local snapshot instead and names itself, so the server can end the session it holds for that endpoint. The client silences itself once this call succeeds rather than waiting for a routed `stop`, which by definition cannot reach it. 
  @BuiltValueField(wireName: r'handoffFrom')
  String? get handoffFrom;

  PlaybackSessionCreate._();

  factory PlaybackSessionCreate([void updates(PlaybackSessionCreateBuilder b)]) = _$PlaybackSessionCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaybackSessionCreateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaybackSessionCreate> get serializer => _$PlaybackSessionCreateSerializer();
}

class _$PlaybackSessionCreateSerializer implements PrimitiveSerializer<PlaybackSessionCreate> {
  @override
  final Iterable<Type> types = const [PlaybackSessionCreate, _$PlaybackSessionCreate];

  @override
  final String wireName = r'PlaybackSessionCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaybackSessionCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'endpointId';
    yield serializers.serialize(
      object.endpointId,
      specifiedType: const FullType(String),
    );
    yield r'itemPids';
    yield serializers.serialize(
      object.itemPids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.index != null) {
      yield r'index';
      yield serializers.serialize(
        object.index,
        specifiedType: const FullType(int),
      );
    }
    if (object.positionMs != null) {
      yield r'positionMs';
      yield serializers.serialize(
        object.positionMs,
        specifiedType: const FullType(int),
      );
    }
    if (object.play != null) {
      yield r'play';
      yield serializers.serialize(
        object.play,
        specifiedType: const FullType(bool),
      );
    }
    if (object.rate != null) {
      yield r'rate';
      yield serializers.serialize(
        object.rate,
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
    if (object.handoffFrom != null) {
      yield r'handoffFrom';
      yield serializers.serialize(
        object.handoffFrom,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaybackSessionCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaybackSessionCreateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'endpointId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.endpointId = valueDes;
          break;
        case r'itemPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.itemPids.replace(valueDes);
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
        case r'play':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.play = valueDes;
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
        case r'handoffFrom':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.handoffFrom = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaybackSessionCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaybackSessionCreateBuilder();
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

