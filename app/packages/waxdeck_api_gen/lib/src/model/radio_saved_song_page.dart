//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/radio_saved_song.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'radio_saved_song_page.g.dart';

/// One keyset-paginated page of saved songs.
///
/// Properties:
/// * [songs] - Songs newest first.
/// * [nextCursor] - Opaque cursor for the next page. Absent on the last page.
@BuiltValue()
abstract class RadioSavedSongPage implements Built<RadioSavedSongPage, RadioSavedSongPageBuilder> {
  /// Songs newest first.
  @BuiltValueField(wireName: r'songs')
  BuiltList<RadioSavedSong> get songs;

  /// Opaque cursor for the next page. Absent on the last page.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  RadioSavedSongPage._();

  factory RadioSavedSongPage([void updates(RadioSavedSongPageBuilder b)]) = _$RadioSavedSongPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RadioSavedSongPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RadioSavedSongPage> get serializer => _$RadioSavedSongPageSerializer();
}

class _$RadioSavedSongPageSerializer implements PrimitiveSerializer<RadioSavedSongPage> {
  @override
  final Iterable<Type> types = const [RadioSavedSongPage, _$RadioSavedSongPage];

  @override
  final String wireName = r'RadioSavedSongPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RadioSavedSongPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'songs';
    yield serializers.serialize(
      object.songs,
      specifiedType: const FullType(BuiltList, [FullType(RadioSavedSong)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RadioSavedSongPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RadioSavedSongPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'songs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RadioSavedSong)]),
          ) as BuiltList<RadioSavedSong>;
          result.songs.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextCursor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RadioSavedSongPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RadioSavedSongPageBuilder();
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

