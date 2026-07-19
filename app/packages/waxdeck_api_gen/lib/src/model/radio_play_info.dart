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
@BuiltValue()
abstract class RadioPlayInfo implements Built<RadioPlayInfo, RadioPlayInfoBuilder> {
  /// Origin-relative proxied stream URL carrying a short-lived media token. 
  @BuiltValueField(wireName: r'url')
  String get url;

  /// The most recent in-stream ICY title the proxy observed for this station. Present only while a proxied listener has the stream open and the station publishes StreamTitle metadata; it reflects what the station last announced, not a guarantee of what is audible right now. The listener may be any user (stations are a shared library, so the field's presence reveals that someone on this server is streaming the station). The value is best-effort UTF-8 from an untrusted station and should be treated as plain display text; an empty announced title is reported as absent. Clients that show it should re-poll this endpoint on the order of every 15 seconds during playback. Every response carries a freshly tokenized url; while already playing, ignore the new url and keep the open stream (polling opens no new connection to the station). On a first request, before anyone has the stream open, the field is necessarily absent. 
  @BuiltValueField(wireName: r'nowPlaying')
  String? get nowPlaying;

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

