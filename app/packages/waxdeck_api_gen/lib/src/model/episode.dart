//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/chapter_mark.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:waxdeck_api_gen/src/model/episode_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'episode.g.dart';

/// Full detail for one episode.
///
/// Properties:
/// * [pid] - Type-prefixed ULID.
/// * [mediaType] 
/// * [title] - Display title.
/// * [artist] - Primary display artist / author / show name.
/// * [album] - Album / series / podcast title, when applicable.
/// * [durationMs] - Duration in milliseconds. For a multi-file audiobook this is the total across all parts; for a not-yet-fetched podcast episode it is the feed-declared duration, or 0 when the feed declares none. 
/// * [artUrl] - Origin-relative URL of the item's artwork endpoint. Always populated; the endpoint itself returns 404 for items with no artwork, so clients keep a placeholder ready. 
/// * [showPid] - The show this episode belongs to.
/// * [season] - Season number, when the feed declares one.
/// * [episodeNumber] - Episode number, when the feed declares one.
/// * [episodeType] - Feed-declared episode type (`full`, `trailer`, `bonus`). Open set; treat unknown values like `full`. 
/// * [publishedAt] - Publication time. When the feed declares none, the server substitutes the time it first saw the episode, so ordering and paging stay total. 
/// * [downloaded] - Whether the audio is on the server. Playback needs the fetch first: play-info for a not-yet-fetched episode answers `conflict`, and the episode fetch endpoint queues the download. 
/// * [fetchState] - Present while a server-side fetch is queued or after one failed: `queued` or `failed`. Absent otherwise. Open set; treat unknown values as `queued`. 
/// * [fetchError] - Why the last fetch attempt failed (`fetchState` is `failed`). Retrying the fetch endpoint re-queues it. 
/// * [explicit] - Feed-declared explicit flag.
/// * [hasTranscript] - Whether a transcript is available.
/// * [descriptionHtml] - Show notes as sanitized HTML (server-side allowlist; safe to render directly). 
/// * [link] - The episode's web page, when the feed declares one.
/// * [chapters] - Chapter marks, ordered by `startMs`.
@BuiltValue()
abstract class Episode implements EpisodeSummary, Built<Episode, EpisodeBuilder> {
  /// Chapter marks, ordered by `startMs`.
  @BuiltValueField(wireName: r'chapters')
  BuiltList<ChapterMark>? get chapters;

  /// The episode's web page, when the feed declares one.
  @BuiltValueField(wireName: r'link')
  String? get link;

  /// Show notes as sanitized HTML (server-side allowlist; safe to render directly). 
  @BuiltValueField(wireName: r'descriptionHtml')
  String? get descriptionHtml;

  Episode._();

  factory Episode([void updates(EpisodeBuilder b)]) = _$Episode;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EpisodeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Episode> get serializer => _$EpisodeSerializer();
}

class _$EpisodeSerializer implements PrimitiveSerializer<Episode> {
  @override
  final Iterable<Type> types = const [Episode, _$Episode];

  @override
  final String wireName = r'Episode';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Episode object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.fetchError != null) {
      yield r'fetchError';
      yield serializers.serialize(
        object.fetchError,
        specifiedType: const FullType(String),
      );
    }
    if (object.fetchState != null) {
      yield r'fetchState';
      yield serializers.serialize(
        object.fetchState,
        specifiedType: const FullType(String),
      );
    }
    if (object.chapters != null) {
      yield r'chapters';
      yield serializers.serialize(
        object.chapters,
        specifiedType: const FullType(BuiltList, [FullType(ChapterMark)]),
      );
    }
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    yield r'publishedAt';
    yield serializers.serialize(
      object.publishedAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.album != null) {
      yield r'album';
      yield serializers.serialize(
        object.album,
        specifiedType: const FullType(String),
      );
    }
    if (object.link != null) {
      yield r'link';
      yield serializers.serialize(
        object.link,
        specifiedType: const FullType(String),
      );
    }
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'mediaType';
    yield serializers.serialize(
      object.mediaType,
      specifiedType: const FullType(MediaType),
    );
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.episodeNumber != null) {
      yield r'episodeNumber';
      yield serializers.serialize(
        object.episodeNumber,
        specifiedType: const FullType(int),
      );
    }
    yield r'downloaded';
    yield serializers.serialize(
      object.downloaded,
      specifiedType: const FullType(bool),
    );
    if (object.artUrl != null) {
      yield r'artUrl';
      yield serializers.serialize(
        object.artUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.hasTranscript != null) {
      yield r'hasTranscript';
      yield serializers.serialize(
        object.hasTranscript,
        specifiedType: const FullType(bool),
      );
    }
    if (object.explicit != null) {
      yield r'explicit';
      yield serializers.serialize(
        object.explicit,
        specifiedType: const FullType(bool),
      );
    }
    if (object.episodeType != null) {
      yield r'episodeType';
      yield serializers.serialize(
        object.episodeType,
        specifiedType: const FullType(String),
      );
    }
    yield r'showPid';
    yield serializers.serialize(
      object.showPid,
      specifiedType: const FullType(String),
    );
    if (object.season != null) {
      yield r'season';
      yield serializers.serialize(
        object.season,
        specifiedType: const FullType(int),
      );
    }
    if (object.descriptionHtml != null) {
      yield r'descriptionHtml';
      yield serializers.serialize(
        object.descriptionHtml,
        specifiedType: const FullType(String),
      );
    }
    yield r'durationMs';
    yield serializers.serialize(
      object.durationMs,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Episode object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EpisodeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'fetchError':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fetchError = valueDes;
          break;
        case r'fetchState':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fetchState = valueDes;
          break;
        case r'chapters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ChapterMark)]),
          ) as BuiltList<ChapterMark>;
          result.chapters.replace(valueDes);
          break;
        case r'artist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artist = valueDes;
          break;
        case r'publishedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.publishedAt = valueDes;
          break;
        case r'album':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.album = valueDes;
          break;
        case r'link':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.link = valueDes;
          break;
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'mediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaType),
          ) as MediaType;
          result.mediaType = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'episodeNumber':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.episodeNumber = valueDes;
          break;
        case r'downloaded':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.downloaded = valueDes;
          break;
        case r'artUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artUrl = valueDes;
          break;
        case r'hasTranscript':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasTranscript = valueDes;
          break;
        case r'explicit':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.explicit = valueDes;
          break;
        case r'episodeType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.episodeType = valueDes;
          break;
        case r'showPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.showPid = valueDes;
          break;
        case r'season':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.season = valueDes;
          break;
        case r'descriptionHtml':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.descriptionHtml = valueDes;
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
  Episode deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EpisodeBuilder();
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

