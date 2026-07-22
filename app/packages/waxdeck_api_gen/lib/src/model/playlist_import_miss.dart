//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_import_miss.g.dart';

/// One unmatched import entry.
///
/// Properties:
/// * [artist] - The entry's artist, as exported.
/// * [title] - The entry's title, as exported.
/// * [album] - The entry's album, as exported.
/// * [durationMs] - The entry's duration, when the export carried one.
@BuiltValue()
abstract class PlaylistImportMiss implements Built<PlaylistImportMiss, PlaylistImportMissBuilder> {
  /// The entry's artist, as exported.
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// The entry's title, as exported.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// The entry's album, as exported.
  @BuiltValueField(wireName: r'album')
  String? get album;

  /// The entry's duration, when the export carried one.
  @BuiltValueField(wireName: r'durationMs')
  int? get durationMs;

  PlaylistImportMiss._();

  factory PlaylistImportMiss([void updates(PlaylistImportMissBuilder b)]) = _$PlaylistImportMiss;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistImportMissBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistImportMiss> get serializer => _$PlaylistImportMissSerializer();
}

class _$PlaylistImportMissSerializer implements PrimitiveSerializer<PlaylistImportMiss> {
  @override
  final Iterable<Type> types = const [PlaylistImportMiss, _$PlaylistImportMiss];

  @override
  final String wireName = r'PlaylistImportMiss';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistImportMiss object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.album != null) {
      yield r'album';
      yield serializers.serialize(
        object.album,
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
    PlaylistImportMiss object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistImportMissBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'album':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.album = valueDes;
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
  PlaylistImportMiss deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistImportMissBuilder();
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

