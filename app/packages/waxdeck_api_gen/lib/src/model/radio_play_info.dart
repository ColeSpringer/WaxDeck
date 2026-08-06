//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'radio_play_info.g.dart';

/// A resolved, tokenized station stream.
///
/// Properties:
/// * [url] - Origin-relative proxied stream URL carrying a short-lived media token. 
/// * [nowPlaying] - The most recent in-stream ICY title the proxy observed for this station. Present only while a proxied listener has the stream open and the station publishes StreamTitle metadata; it reflects what the station last announced, not a guarantee of what is audible right now. The listener may be any user (stations are a shared library, so the field's presence reveals that someone on this server is streaming the station). The value is best-effort UTF-8 from an untrusted station and should be treated as plain display text; an empty announced title is reported as absent. Clients that show it should re-poll this endpoint on the order of every 15 seconds during playback. Every response carries a freshly tokenized url; while already playing, ignore the new url and keep the open stream (polling opens no new connection to the station). On a first request, before anyone has the stream open, the field is necessarily absent. 
/// * [nowPlayingItemPid] - A library track this server matched `nowPlaying` to, when it recognised one. Present so a full-screen player can draw the song's own cover art instead of the station logo; absent is the common case and is not a failure, so a client that cannot match must fall back to the station's artwork rather than showing a gap. The match is a best-effort text lookup against the catalog and is never authoritative: it does not mean this server is playing that file, and it is deliberately not used for scrobbling, which reports what the station announced. 
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

