//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/prefs.dart';
import 'package:waxdeck_api_gen/src/model/play_state.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'server_sync_event.g.dart';

/// One change to the calling user's server-side state, with the current value hydrated fresh. `kind` is a string, not a closed enum, so new kinds can appear; clients must skip events whose `kind` they do not recognize. 
///
/// Properties:
/// * [kind] - What changed: `play-state` (carries `pid` and `playState`) or `prefs` (carries `prefs`). 
/// * [pid] - The item whose state changed (`play-state` only).
/// * [playState] 
/// * [prefs] 
@BuiltValue()
abstract class ServerSyncEvent implements Built<ServerSyncEvent, ServerSyncEventBuilder> {
  /// What changed: `play-state` (carries `pid` and `playState`) or `prefs` (carries `prefs`). 
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// The item whose state changed (`play-state` only).
  @BuiltValueField(wireName: r'pid')
  String? get pid;

  @BuiltValueField(wireName: r'playState')
  PlayState? get playState;

  @BuiltValueField(wireName: r'prefs')
  Prefs? get prefs;

  ServerSyncEvent._();

  factory ServerSyncEvent([void updates(ServerSyncEventBuilder b)]) = _$ServerSyncEvent;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServerSyncEventBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServerSyncEvent> get serializer => _$ServerSyncEventSerializer();
}

class _$ServerSyncEventSerializer implements PrimitiveSerializer<ServerSyncEvent> {
  @override
  final Iterable<Type> types = const [ServerSyncEvent, _$ServerSyncEvent];

  @override
  final String wireName = r'ServerSyncEvent';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServerSyncEvent object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    if (object.pid != null) {
      yield r'pid';
      yield serializers.serialize(
        object.pid,
        specifiedType: const FullType(String),
      );
    }
    if (object.playState != null) {
      yield r'playState';
      yield serializers.serialize(
        object.playState,
        specifiedType: const FullType(PlayState),
      );
    }
    if (object.prefs != null) {
      yield r'prefs';
      yield serializers.serialize(
        object.prefs,
        specifiedType: const FullType(Prefs),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ServerSyncEvent object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ServerSyncEventBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'playState':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlayState),
          ) as PlayState;
          result.playState.replace(valueDes);
          break;
        case r'prefs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Prefs),
          ) as Prefs;
          result.prefs.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServerSyncEvent deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServerSyncEventBuilder();
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

