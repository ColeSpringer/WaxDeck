//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/art_source.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'radio_play_info.g.dart';

/// A resolved, tokenized station stream.
///
/// Properties:
/// * [url] - Origin-relative proxied stream URL carrying a short-lived media token. 
/// * [nowPlaying] - The most recent in-stream ICY title the proxy observed for this station. Present only while a proxied listener has the stream open and the station publishes StreamTitle metadata; it reflects what the station last announced, not a guarantee of what is audible right now. The listener may be any user (stations are a shared library, so the field's presence reveals that someone on this server is streaming the station). The value is best-effort UTF-8 from an untrusted station and should be treated as plain display text; an empty announced title is reported as absent. Clients that show it should re-poll this endpoint on the order of every 15 seconds during playback. Every response carries a freshly tokenized url; while already playing, ignore the new url and keep the open stream (polling opens no new connection to the station). On a first request, before anyone has the stream open, the field is necessarily absent. 
/// * [nowPlayingItemPid] - A library track this server matched `nowPlaying` to, when it recognised one. Present so a full-screen player can draw the song's own cover art instead of the station logo; absent is the common case and is not a failure, so a client that cannot match must fall back to the station's artwork rather than showing a gap. The match is a best-effort text lookup against the catalog and is never authoritative: it does not mean this server is playing that file, and it is deliberately not used for scrobbling, which reports what the station announced. 
/// * [nowPlayingArtKey] - An opaque token naming the cover this server holds for what the station last announced, present only when it holds one. It covers both of the artwork rungs below the library match - the picture the station announced in its own stream, and the MusicBrainz lookup under that - and does two jobs: it says there is an image to ask for, and it is what makes the image URL change when the station changes what it is playing.  Pass it as `v` on `GET /radio/stations/{pid}/now-playing-art`. A client that omits it gets a 404 - the endpoint is addressed by token, not by whatever is announced at the moment the image request lands, so the bytes behind one URL never change and the long `Cache-Control` they carry is true.  The fetch behind it is asynchronous, so the field appears on a later poll rather than on the one that started it. Absent means draw the local match if there is one, then the station logo, then the station mark. A station that announces no picture of its own leaves this absent for good while the external rung is switched off.  `nowPlayingArtSource` alongside it says which of the two rungs answered, so a face can caption the picture rather than presenting a third party's cover as the station's own. 
/// * [nowPlayingArtSource] 
/// * [nowPlayingSaved] - Whether the caller has already kept what the station is announcing, so the heart on a playing surface draws filled. Per caller rather than per station: saved songs are personal. Absent means the same as false and is what a response with no `nowPlaying` carries.  This rides the poll the surfaces already run, which is what keeps the heart honest across devices: a save made on the phone fills the desktop's heart within one poll, and a rollover empties it. Membership is decided on the same identity the save uses - the parsed artist and title where the line splits, the raw line where it does not - so a listener who saved this song from another station sees it filled here too. 
/// * [nowPlayingSavedPid] - The saved song's pid, present exactly when `nowPlayingSaved` is true. Carried so an untap can `DELETE /radio/saved/{pid}` without first fetching the list. 
@BuiltValue()
abstract class RadioPlayInfo implements Built<RadioPlayInfo, RadioPlayInfoBuilder> {
  /// Origin-relative proxied stream URL carrying a short-lived media token. 
  @BuiltValueField(wireName: r'url')
  String get url;

  /// The most recent in-stream ICY title the proxy observed for this station. Present only while a proxied listener has the stream open and the station publishes StreamTitle metadata; it reflects what the station last announced, not a guarantee of what is audible right now. The listener may be any user (stations are a shared library, so the field's presence reveals that someone on this server is streaming the station). The value is best-effort UTF-8 from an untrusted station and should be treated as plain display text; an empty announced title is reported as absent. Clients that show it should re-poll this endpoint on the order of every 15 seconds during playback. Every response carries a freshly tokenized url; while already playing, ignore the new url and keep the open stream (polling opens no new connection to the station). On a first request, before anyone has the stream open, the field is necessarily absent. 
  @BuiltValueField(wireName: r'nowPlaying')
  String? get nowPlaying;

  /// A library track this server matched `nowPlaying` to, when it recognised one. Present so a full-screen player can draw the song's own cover art instead of the station logo; absent is the common case and is not a failure, so a client that cannot match must fall back to the station's artwork rather than showing a gap. The match is a best-effort text lookup against the catalog and is never authoritative: it does not mean this server is playing that file, and it is deliberately not used for scrobbling, which reports what the station announced. 
  @BuiltValueField(wireName: r'nowPlayingItemPid')
  String? get nowPlayingItemPid;

  /// An opaque token naming the cover this server holds for what the station last announced, present only when it holds one. It covers both of the artwork rungs below the library match - the picture the station announced in its own stream, and the MusicBrainz lookup under that - and does two jobs: it says there is an image to ask for, and it is what makes the image URL change when the station changes what it is playing.  Pass it as `v` on `GET /radio/stations/{pid}/now-playing-art`. A client that omits it gets a 404 - the endpoint is addressed by token, not by whatever is announced at the moment the image request lands, so the bytes behind one URL never change and the long `Cache-Control` they carry is true.  The fetch behind it is asynchronous, so the field appears on a later poll rather than on the one that started it. Absent means draw the local match if there is one, then the station logo, then the station mark. A station that announces no picture of its own leaves this absent for good while the external rung is switched off.  `nowPlayingArtSource` alongside it says which of the two rungs answered, so a face can caption the picture rather than presenting a third party's cover as the station's own. 
  @BuiltValueField(wireName: r'nowPlayingArtKey')
  String? get nowPlayingArtKey;

  @BuiltValueField(wireName: r'nowPlayingArtSource')
  ArtSource? get nowPlayingArtSource;

  /// Whether the caller has already kept what the station is announcing, so the heart on a playing surface draws filled. Per caller rather than per station: saved songs are personal. Absent means the same as false and is what a response with no `nowPlaying` carries.  This rides the poll the surfaces already run, which is what keeps the heart honest across devices: a save made on the phone fills the desktop's heart within one poll, and a rollover empties it. Membership is decided on the same identity the save uses - the parsed artist and title where the line splits, the raw line where it does not - so a listener who saved this song from another station sees it filled here too. 
  @BuiltValueField(wireName: r'nowPlayingSaved')
  bool? get nowPlayingSaved;

  /// The saved song's pid, present exactly when `nowPlayingSaved` is true. Carried so an untap can `DELETE /radio/saved/{pid}` without first fetching the list. 
  @BuiltValueField(wireName: r'nowPlayingSavedPid')
  String? get nowPlayingSavedPid;

  RadioPlayInfo._();

  factory RadioPlayInfo([void updates(RadioPlayInfoBuilder b)]) = _$RadioPlayInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RadioPlayInfoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RadioPlayInfo> get serializer => _$RadioPlayInfoSerializer();
}

class _$RadioPlayInfoSerializer implements PrimitiveSerializer<RadioPlayInfo> {
  @override
  final Iterable<Type> types = const [RadioPlayInfo, _$RadioPlayInfo];

  @override
  final String wireName = r'RadioPlayInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RadioPlayInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'url';
    yield serializers.serialize(
      object.url,
      specifiedType: const FullType(String),
    );
    if (object.nowPlaying != null) {
      yield r'nowPlaying';
      yield serializers.serialize(
        object.nowPlaying,
        specifiedType: const FullType(String),
      );
    }
    if (object.nowPlayingItemPid != null) {
      yield r'nowPlayingItemPid';
      yield serializers.serialize(
        object.nowPlayingItemPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.nowPlayingArtKey != null) {
      yield r'nowPlayingArtKey';
      yield serializers.serialize(
        object.nowPlayingArtKey,
        specifiedType: const FullType(String),
      );
    }
    if (object.nowPlayingArtSource != null) {
      yield r'nowPlayingArtSource';
      yield serializers.serialize(
        object.nowPlayingArtSource,
        specifiedType: const FullType(ArtSource),
      );
    }
    if (object.nowPlayingSaved != null) {
      yield r'nowPlayingSaved';
      yield serializers.serialize(
        object.nowPlayingSaved,
        specifiedType: const FullType(bool),
      );
    }
    if (object.nowPlayingSavedPid != null) {
      yield r'nowPlayingSavedPid';
      yield serializers.serialize(
        object.nowPlayingSavedPid,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RadioPlayInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RadioPlayInfoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'nowPlaying':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nowPlaying = valueDes;
          break;
        case r'nowPlayingItemPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nowPlayingItemPid = valueDes;
          break;
        case r'nowPlayingArtKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nowPlayingArtKey = valueDes;
          break;
        case r'nowPlayingArtSource':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ArtSource),
          ) as ArtSource;
          result.nowPlayingArtSource.replace(valueDes);
          break;
        case r'nowPlayingSaved':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.nowPlayingSaved = valueDes;
          break;
        case r'nowPlayingSavedPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nowPlayingSavedPid = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RadioPlayInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RadioPlayInfoBuilder();
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

