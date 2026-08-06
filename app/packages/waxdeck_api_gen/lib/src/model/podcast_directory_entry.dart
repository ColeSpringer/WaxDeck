//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'podcast_directory_entry.g.dart';

/// One podcast directory match.
///
/// Properties:
/// * [name] - Show name as the directory lists it.
/// * [feedUrl] - The show's RSS feed URL, ready to POST to `/podcasts`. A match with no usable feed URL is dropped server-side rather than returned as unsubscribable. 
/// * [author] - Publisher or author name.
/// * [artworkUrl] - Show artwork as the directory lists it, drawn directly by the client. There is no proxy for a directory match: cover art is addressed by show pid and a match has none until it is subscribed to. 
/// * [genre] - Primary directory genre.
/// * [episodeCount] - Directory-reported episode count, 0 when unknown.
@BuiltValue()
abstract class PodcastDirectoryEntry implements Built<PodcastDirectoryEntry, PodcastDirectoryEntryBuilder> {
  /// Show name as the directory lists it.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// The show's RSS feed URL, ready to POST to `/podcasts`. A match with no usable feed URL is dropped server-side rather than returned as unsubscribable. 
  @BuiltValueField(wireName: r'feedUrl')
  String get feedUrl;

  /// Publisher or author name.
  @BuiltValueField(wireName: r'author')
  String? get author;

  /// Show artwork as the directory lists it, drawn directly by the client. There is no proxy for a directory match: cover art is addressed by show pid and a match has none until it is subscribed to. 
  @BuiltValueField(wireName: r'artworkUrl')
  String? get artworkUrl;

  /// Primary directory genre.
  @BuiltValueField(wireName: r'genre')
  String? get genre;

  /// Directory-reported episode count, 0 when unknown.
  @BuiltValueField(wireName: r'episodeCount')
  int? get episodeCount;

  PodcastDirectoryEntry._();

  factory PodcastDirectoryEntry([void updates(PodcastDirectoryEntryBuilder b)]) = _$PodcastDirectoryEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PodcastDirectoryEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PodcastDirectoryEntry> get serializer => _$PodcastDirectoryEntrySerializer();
}

class _$PodcastDirectoryEntrySerializer implements PrimitiveSerializer<PodcastDirectoryEntry> {
  @override
  final Iterable<Type> types = const [PodcastDirectoryEntry, _$PodcastDirectoryEntry];

  @override
  final String wireName = r'PodcastDirectoryEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PodcastDirectoryEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'feedUrl';
    yield serializers.serialize(
      object.feedUrl,
      specifiedType: const FullType(String),
    );
    if (object.author != null) {
      yield r'author';
      yield serializers.serialize(
        object.author,
        specifiedType: const FullType(String),
      );
    }
    if (object.artworkUrl != null) {
      yield r'artworkUrl';
      yield serializers.serialize(
        object.artworkUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.genre != null) {
      yield r'genre';
      yield serializers.serialize(
        object.genre,
        specifiedType: const FullType(String),
      );
    }
    if (object.episodeCount != null) {
      yield r'episodeCount';
      yield serializers.serialize(
        object.episodeCount,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PodcastDirectoryEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PodcastDirectoryEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'feedUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.feedUrl = valueDes;
          break;
        case r'author':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.author = valueDes;
          break;
        case r'artworkUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artworkUrl = valueDes;
          break;
        case r'genre':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.genre = valueDes;
          break;
        case r'episodeCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.episodeCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PodcastDirectoryEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PodcastDirectoryEntryBuilder();
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

