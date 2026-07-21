//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playback_session_entry.g.dart';

/// One queue entry of a playback session, hydrated for display.
///
/// Properties:
/// * [pid] - The item's PID.
/// * [title] - Display title.
/// * [artist] - Display artist, when the item has one.
/// * [durationMs] - Item duration in milliseconds, when known.
@BuiltValue()
abstract class PlaybackSessionEntry implements Built<PlaybackSessionEntry, PlaybackSessionEntryBuilder> {
  /// The item's PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Display title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Display artist, when the item has one.
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// Item duration in milliseconds, when known.
  @BuiltValueField(wireName: r'durationMs')
  int? get durationMs;

  PlaybackSessionEntry._();

  factory PlaybackSessionEntry([void updates(PlaybackSessionEntryBuilder b)]) = _$PlaybackSessionEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaybackSessionEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaybackSessionEntry> get serializer => _$PlaybackSessionEntrySerializer();
}

class _$PlaybackSessionEntrySerializer implements PrimitiveSerializer<PlaybackSessionEntry> {
  @override
  final Iterable<Type> types = const [PlaybackSessionEntry, _$PlaybackSessionEntry];

  @override
  final String wireName = r'PlaybackSessionEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaybackSessionEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    if (object.durationMs != null) {
      yield r'durationMs';
      yield serializers.serialize(
        object.durationMs,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaybackSessionEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaybackSessionEntryBuilder result,
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
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'artist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artist = valueDes;
          break;
        case r'durationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMs = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaybackSessionEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaybackSessionEntryBuilder();
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

