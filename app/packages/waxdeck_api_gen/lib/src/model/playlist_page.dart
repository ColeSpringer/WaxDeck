//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/playlist.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_page.g.dart';

/// One keyset-paginated page of playlists.
///
/// Properties:
/// * [playlists] - Playlists ordered by name then pid.
/// * [nextCursor] - Opaque cursor for the next page. Absent on the last page.
@BuiltValue()
abstract class PlaylistPage implements Built<PlaylistPage, PlaylistPageBuilder> {
  /// Playlists ordered by name then pid.
  @BuiltValueField(wireName: r'playlists')
  BuiltList<Playlist> get playlists;

  /// Opaque cursor for the next page. Absent on the last page.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  PlaylistPage._();

  factory PlaylistPage([void updates(PlaylistPageBuilder b)]) = _$PlaylistPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistPage> get serializer => _$PlaylistPageSerializer();
}

class _$PlaylistPageSerializer implements PrimitiveSerializer<PlaylistPage> {
  @override
  final Iterable<Type> types = const [PlaylistPage, _$PlaylistPage];

  @override
  final String wireName = r'PlaylistPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'playlists';
    yield serializers.serialize(
      object.playlists,
      specifiedType: const FullType(BuiltList, [FullType(Playlist)]),
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
    PlaylistPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'playlists':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Playlist)]),
          ) as BuiltList<Playlist>;
          result.playlists.replace(valueDes);
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
  PlaylistPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistPageBuilder();
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

