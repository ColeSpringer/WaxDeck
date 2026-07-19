//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/subscription.dart';
import 'package:waxdeck_api_gen/src/model/book_settings.dart';
import 'package:waxdeck_api_gen/src/model/prefs.dart';
import 'package:waxdeck_api_gen/src/model/play_state.dart';
import 'package:waxdeck_api_gen/src/model/playlist.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'server_sync_event.g.dart';

/// One change to server-side state visible to the calling user (their own state, plus other users' shared playlists), with the current value hydrated fresh. `kind` is a string, not a closed enum, so new kinds can appear; clients must skip events whose `kind` they do not recognize. Hydrated `playlist` payloads omit a smart playlist's computed `itemCount`, like list pages. 
///
/// Properties:
/// * [kind] - What changed: `play-state` (carries `pid` and `playState`), `prefs` (carries `prefs`), `subscription` (carries `pid`, the show; `subscription` is the current state, absent when the caller unsubscribed), `book-settings` (carries `pid`, the book, and `bookSettings`), or `playlist` (carries `pid`; `playlist` is the current state, absent when the playlist was deleted or replaced under a new pid). 
/// * [pid] - The item, show, book, or playlist the event is about (absent for `prefs`). 
/// * [playState] 
/// * [prefs] 
/// * [subscription] 
/// * [bookSettings] 
/// * [playlist] 
@BuiltValue()
abstract class ServerSyncEvent implements Built<ServerSyncEvent, ServerSyncEventBuilder> {
  /// What changed: `play-state` (carries `pid` and `playState`), `prefs` (carries `prefs`), `subscription` (carries `pid`, the show; `subscription` is the current state, absent when the caller unsubscribed), `book-settings` (carries `pid`, the book, and `bookSettings`), or `playlist` (carries `pid`; `playlist` is the current state, absent when the playlist was deleted or replaced under a new pid). 
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// The item, show, book, or playlist the event is about (absent for `prefs`). 
  @BuiltValueField(wireName: r'pid')
  String? get pid;

  @BuiltValueField(wireName: r'playState')
  PlayState? get playState;

  @BuiltValueField(wireName: r'prefs')
  Prefs? get prefs;

  @BuiltValueField(wireName: r'subscription')
  Subscription? get subscription;

  @BuiltValueField(wireName: r'bookSettings')
  BookSettings? get bookSettings;

  @BuiltValueField(wireName: r'playlist')
  Playlist? get playlist;

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
    if (object.subscription != null) {
      yield r'subscription';
      yield serializers.serialize(
        object.subscription,
        specifiedType: const FullType(Subscription),
      );
    }
    if (object.bookSettings != null) {
      yield r'bookSettings';
      yield serializers.serialize(
        object.bookSettings,
        specifiedType: const FullType(BookSettings),
      );
    }
    if (object.playlist != null) {
      yield r'playlist';
      yield serializers.serialize(
        object.playlist,
        specifiedType: const FullType(Playlist),
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
        case r'subscription':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Subscription),
          ) as Subscription;
          result.subscription.replace(valueDes);
          break;
        case r'bookSettings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BookSettings),
          ) as BookSettings;
          result.bookSettings.replace(valueDes);
          break;
        case r'playlist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Playlist),
          ) as Playlist;
          result.playlist.replace(valueDes);
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

