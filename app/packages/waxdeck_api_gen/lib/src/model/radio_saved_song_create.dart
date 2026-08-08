//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'radio_saved_song_create.g.dart';

/// The announcement a listener is keeping. Both fields describe what they saw rather than what the station is announcing by the time this request lands: a station rolls over every few minutes while a client polls every fifteen seconds, so a save resolved server-side against the live title would sometimes keep the next song instead of the tapped one. 
///
/// Properties:
/// * [stationPid] - The station the song was heard on.
/// * [nowPlaying] - The announced line exactly as `nowPlaying` reported it. The server parses it the same way the scrobbler does and stores both the parse and the raw line. 
@BuiltValue()
abstract class RadioSavedSongCreate implements Built<RadioSavedSongCreate, RadioSavedSongCreateBuilder> {
  /// The station the song was heard on.
  @BuiltValueField(wireName: r'stationPid')
  String get stationPid;

  /// The announced line exactly as `nowPlaying` reported it. The server parses it the same way the scrobbler does and stores both the parse and the raw line. 
  @BuiltValueField(wireName: r'nowPlaying')
  String get nowPlaying;

  RadioSavedSongCreate._();

  factory RadioSavedSongCreate([void updates(RadioSavedSongCreateBuilder b)]) = _$RadioSavedSongCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RadioSavedSongCreateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RadioSavedSongCreate> get serializer => _$RadioSavedSongCreateSerializer();
}

class _$RadioSavedSongCreateSerializer implements PrimitiveSerializer<RadioSavedSongCreate> {
  @override
  final Iterable<Type> types = const [RadioSavedSongCreate, _$RadioSavedSongCreate];

  @override
  final String wireName = r'RadioSavedSongCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RadioSavedSongCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'stationPid';
    yield serializers.serialize(
      object.stationPid,
      specifiedType: const FullType(String),
    );
    yield r'nowPlaying';
    yield serializers.serialize(
      object.nowPlaying,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RadioSavedSongCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RadioSavedSongCreateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'stationPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.stationPid = valueDes;
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
  RadioSavedSongCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RadioSavedSongCreateBuilder();
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

