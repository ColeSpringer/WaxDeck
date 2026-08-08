//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'radio_saved_song.g.dart';

/// One song a listener kept off the air. Deliberately not a library item: nothing here plays, and the rows exist to be hunted down and crossed off. 
///
/// Properties:
/// * [pid] - Type-prefixed ULID.
/// * [nowPlaying] - The announcement as the station sent it, snapshotted at save time. Best-effort UTF-8 from an untrusted host; treat as plain display text. This is what a row draws when nothing parsed out of it. 
/// * [artist] - The artist, where the announced line split into one. Absent is ordinary rather than a failure - stations announce in every shape there is - and a row without it still names the song by its raw line.  **Album is deliberately absent from this schema.** ICY metadata is one line, so there is nothing honest to put in one; a row that names an album would be guessing. 
/// * [title] - The song title, where the announced line split into one.
/// * [stationPid] - The station this was heard on, when it is still in the library. Absent once the station is removed - the row outlives it, because what was kept is the song. 
/// * [stationName] - The station's name as it was at save time, snapshotted so a row still says where it came from after a rename or a removal. 
/// * [heardAt] - When the listener kept it.
/// * [inLibraryPid] - A library track this server matched the row to, resolved at read time under the caller's own visibility. Present means the hunt is over and a client may say so; absent is the common case and the reason the list exists. The match is the same best-effort text lookup `nowPlayingItemPid` uses and is never authoritative, so it is a marker rather than a playable handle. 
/// * [hasArt] - Whether a cover was snapshotted with this row, and so whether `GET /radio/saved/{pid}/art` has bytes to answer. False is ordinary: the picture is copied from whatever the artwork ladder held at save time, and most announcements have nothing on it. Draw a monogram, which is a designed state. 
@BuiltValue()
abstract class RadioSavedSong implements Built<RadioSavedSong, RadioSavedSongBuilder> {
  /// Type-prefixed ULID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// The announcement as the station sent it, snapshotted at save time. Best-effort UTF-8 from an untrusted host; treat as plain display text. This is what a row draws when nothing parsed out of it. 
  @BuiltValueField(wireName: r'nowPlaying')
  String get nowPlaying;

  /// The artist, where the announced line split into one. Absent is ordinary rather than a failure - stations announce in every shape there is - and a row without it still names the song by its raw line.  **Album is deliberately absent from this schema.** ICY metadata is one line, so there is nothing honest to put in one; a row that names an album would be guessing. 
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// The song title, where the announced line split into one.
  @BuiltValueField(wireName: r'title')
  String? get title;

  /// The station this was heard on, when it is still in the library. Absent once the station is removed - the row outlives it, because what was kept is the song. 
  @BuiltValueField(wireName: r'stationPid')
  String? get stationPid;

  /// The station's name as it was at save time, snapshotted so a row still says where it came from after a rename or a removal. 
  @BuiltValueField(wireName: r'stationName')
  String get stationName;

  /// When the listener kept it.
  @BuiltValueField(wireName: r'heardAt')
  DateTime get heardAt;

  /// A library track this server matched the row to, resolved at read time under the caller's own visibility. Present means the hunt is over and a client may say so; absent is the common case and the reason the list exists. The match is the same best-effort text lookup `nowPlayingItemPid` uses and is never authoritative, so it is a marker rather than a playable handle. 
  @BuiltValueField(wireName: r'inLibraryPid')
  String? get inLibraryPid;

  /// Whether a cover was snapshotted with this row, and so whether `GET /radio/saved/{pid}/art` has bytes to answer. False is ordinary: the picture is copied from whatever the artwork ladder held at save time, and most announcements have nothing on it. Draw a monogram, which is a designed state. 
  @BuiltValueField(wireName: r'hasArt')
  bool get hasArt;

  RadioSavedSong._();

  factory RadioSavedSong([void updates(RadioSavedSongBuilder b)]) = _$RadioSavedSong;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RadioSavedSongBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RadioSavedSong> get serializer => _$RadioSavedSongSerializer();
}

class _$RadioSavedSongSerializer implements PrimitiveSerializer<RadioSavedSong> {
  @override
  final Iterable<Type> types = const [RadioSavedSong, _$RadioSavedSong];

  @override
  final String wireName = r'RadioSavedSong';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RadioSavedSong object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'nowPlaying';
    yield serializers.serialize(
      object.nowPlaying,
      specifiedType: const FullType(String),
    );
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType(String),
      );
    }
    if (object.stationPid != null) {
      yield r'stationPid';
      yield serializers.serialize(
        object.stationPid,
        specifiedType: const FullType(String),
      );
    }
    yield r'stationName';
    yield serializers.serialize(
      object.stationName,
      specifiedType: const FullType(String),
    );
    yield r'heardAt';
    yield serializers.serialize(
      object.heardAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.inLibraryPid != null) {
      yield r'inLibraryPid';
      yield serializers.serialize(
        object.inLibraryPid,
        specifiedType: const FullType(String),
      );
    }
    yield r'hasArt';
    yield serializers.serialize(
      object.hasArt,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RadioSavedSong object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RadioSavedSongBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'nowPlaying':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nowPlaying = valueDes;
          break;
        case r'artist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artist = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'stationPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.stationPid = valueDes;
          break;
        case r'stationName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.stationName = valueDes;
          break;
        case r'heardAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.heardAt = valueDes;
          break;
        case r'inLibraryPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.inLibraryPid = valueDes;
          break;
        case r'hasArt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasArt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RadioSavedSong deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RadioSavedSongBuilder();
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

