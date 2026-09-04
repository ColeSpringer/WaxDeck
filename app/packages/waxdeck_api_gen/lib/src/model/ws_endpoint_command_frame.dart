//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_endpoint_command_frame.g.dart';

/// Server-to-client command routed to a registered client endpoint. Verbs are the command verbs plus `load` (adopt this queue at this index and position; the client resolves play-info itself). The client executes against its local engine and answers exactly once with a `cmd-result`, then reports state. `sessionId` says which session the command is for, and a client honours a transport verb only for the session it is currently mirroring: `play`, `pause`, `stop`, `next`, `previous`, `seek`, `set-volume`, `set-rate`, `set-repeat`, and `set-shuffle` naming any other session are answered with a `cmd-result` carrying code `no-session`. `load` and `set-queue` install the session they name, so they are the two that arrive for a session the client is not yet mirroring. A matching `stop` ends the mirror: the client stops local playback, forgets the session, and stops reporting under it. A routed change is the listener's own tap, and persists the way the local control does: `set-rate` is written to the show's or book's stored speed, so the next episode reads it back, while music has no stored speed and a rate set on a track lapses at the next track exactly as a local one does. 
///
/// Properties:
/// * [type] - Always `endpoint-cmd`.
/// * [id] - Server-chosen correlation id for the result.
/// * [sessionId] - The session this command belongs to.
/// * [verb] - The command verb.
/// * [itemPids] - For `load` and `set-queue`.
/// * [index] - For `load` and `set-queue`.
/// * [positionMs] - For `load`, `seek`, and optionally `set-queue`.
/// * [play] - For `load`, whether to start playing.
/// * [volume] - For `set-volume`.
/// * [rate] - For `set-rate`.
/// * [repeat] - For `set-repeat`.
/// * [shuffle] - For `set-shuffle`.
@BuiltValue()
abstract class WsEndpointCommandFrame implements Built<WsEndpointCommandFrame, WsEndpointCommandFrameBuilder> {
  /// Always `endpoint-cmd`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// Server-chosen correlation id for the result.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// The session this command belongs to.
  @BuiltValueField(wireName: r'sessionId')
  String get sessionId;

  /// The command verb.
  @BuiltValueField(wireName: r'verb')
  String get verb;

  /// For `load` and `set-queue`.
  @BuiltValueField(wireName: r'itemPids')
  BuiltList<String>? get itemPids;

  /// For `load` and `set-queue`.
  @BuiltValueField(wireName: r'index')
  int? get index;

  /// For `load`, `seek`, and optionally `set-queue`.
  @BuiltValueField(wireName: r'positionMs')
  int? get positionMs;

  /// For `load`, whether to start playing.
  @BuiltValueField(wireName: r'play')
  bool? get play;

  /// For `set-volume`.
  @BuiltValueField(wireName: r'volume')
  double? get volume;

  /// For `set-rate`.
  @BuiltValueField(wireName: r'rate')
  double? get rate;

  /// For `set-repeat`.
  @BuiltValueField(wireName: r'repeat')
  String? get repeat;

  /// For `set-shuffle`.
  @BuiltValueField(wireName: r'shuffle')
  bool? get shuffle;

  WsEndpointCommandFrame._();

  factory WsEndpointCommandFrame([void updates(WsEndpointCommandFrameBuilder b)]) = _$WsEndpointCommandFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsEndpointCommandFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsEndpointCommandFrame> get serializer => _$WsEndpointCommandFrameSerializer();
}

class _$WsEndpointCommandFrameSerializer implements PrimitiveSerializer<WsEndpointCommandFrame> {
  @override
  final Iterable<Type> types = const [WsEndpointCommandFrame, _$WsEndpointCommandFrame];

  @override
  final String wireName = r'WsEndpointCommandFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsEndpointCommandFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'sessionId';
    yield serializers.serialize(
      object.sessionId,
      specifiedType: const FullType(String),
    );
    yield r'verb';
    yield serializers.serialize(
      object.verb,
      specifiedType: const FullType(String),
    );
    if (object.itemPids != null) {
      yield r'itemPids';
      yield serializers.serialize(
        object.itemPids,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
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
    if (object.volume != null) {
      yield r'volume';
      yield serializers.serialize(
        object.volume,
        specifiedType: const FullType(double),
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
  }

  @override
  Object serialize(
    Serializers serializers,
    WsEndpointCommandFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsEndpointCommandFrameBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.type = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'sessionId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sessionId = valueDes;
          break;
        case r'verb':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.verb = valueDes;
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
        case r'volume':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.volume = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WsEndpointCommandFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsEndpointCommandFrameBuilder();
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

