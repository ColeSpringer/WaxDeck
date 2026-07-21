//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'player_endpoint.g.dart';

/// One controllable playback output: a registered first-party client (`client`), a cast device (`cast`), a DLNA renderer (`dlna`), or the server's own audio output (`jukebox`). `kind` is an open string; clients must render unknown kinds as generic endpoints. 
///
/// Properties:
/// * [id] - Endpoint PID. Stable per device across reconnects.
/// * [kind] - `client`, `cast`, `dlna`, or `jukebox`.
/// * [name] - Display name: the device's advertised name, or the client session's device label. 
/// * [online] - Whether the endpoint is reachable right now. Client endpoints are listed only while online; device endpoints persist across discovery sweeps and go offline when they stop answering. 
/// * [shared] - Shared endpoints are visible and controllable by every user. Device endpoints are shared; client endpoints are private to their owner. 
/// * [mine] - True when the endpoint belongs to the caller.
/// * [volumeControl] - Whether `set-volume` works on this endpoint.
/// * [rateControl] - Whether `set-rate` works on this endpoint.
/// * [activeSessionId] - The session currently playing on this endpoint, when there is one visible to the caller. 
@BuiltValue()
abstract class PlayerEndpoint implements Built<PlayerEndpoint, PlayerEndpointBuilder> {
  /// Endpoint PID. Stable per device across reconnects.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// `client`, `cast`, `dlna`, or `jukebox`.
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// Display name: the device's advertised name, or the client session's device label. 
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Whether the endpoint is reachable right now. Client endpoints are listed only while online; device endpoints persist across discovery sweeps and go offline when they stop answering. 
  @BuiltValueField(wireName: r'online')
  bool get online;

  /// Shared endpoints are visible and controllable by every user. Device endpoints are shared; client endpoints are private to their owner. 
  @BuiltValueField(wireName: r'shared')
  bool get shared;

  /// True when the endpoint belongs to the caller.
  @BuiltValueField(wireName: r'mine')
  bool get mine;

  /// Whether `set-volume` works on this endpoint.
  @BuiltValueField(wireName: r'volumeControl')
  bool get volumeControl;

  /// Whether `set-rate` works on this endpoint.
  @BuiltValueField(wireName: r'rateControl')
  bool get rateControl;

  /// The session currently playing on this endpoint, when there is one visible to the caller. 
  @BuiltValueField(wireName: r'activeSessionId')
  String? get activeSessionId;

  PlayerEndpoint._();

  factory PlayerEndpoint([void updates(PlayerEndpointBuilder b)]) = _$PlayerEndpoint;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlayerEndpointBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlayerEndpoint> get serializer => _$PlayerEndpointSerializer();
}

class _$PlayerEndpointSerializer implements PrimitiveSerializer<PlayerEndpoint> {
  @override
  final Iterable<Type> types = const [PlayerEndpoint, _$PlayerEndpoint];

  @override
  final String wireName = r'PlayerEndpoint';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlayerEndpoint object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'online';
    yield serializers.serialize(
      object.online,
      specifiedType: const FullType(bool),
    );
    yield r'shared';
    yield serializers.serialize(
      object.shared,
      specifiedType: const FullType(bool),
    );
    yield r'mine';
    yield serializers.serialize(
      object.mine,
      specifiedType: const FullType(bool),
    );
    yield r'volumeControl';
    yield serializers.serialize(
      object.volumeControl,
      specifiedType: const FullType(bool),
    );
    yield r'rateControl';
    yield serializers.serialize(
      object.rateControl,
      specifiedType: const FullType(bool),
    );
    if (object.activeSessionId != null) {
      yield r'activeSessionId';
      yield serializers.serialize(
        object.activeSessionId,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlayerEndpoint object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlayerEndpointBuilder result,
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
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'online':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.online = valueDes;
          break;
        case r'shared':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.shared = valueDes;
          break;
        case r'mine':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.mine = valueDes;
          break;
        case r'volumeControl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.volumeControl = valueDes;
          break;
        case r'rateControl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.rateControl = valueDes;
          break;
        case r'activeSessionId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.activeSessionId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlayerEndpoint deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlayerEndpointBuilder();
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

