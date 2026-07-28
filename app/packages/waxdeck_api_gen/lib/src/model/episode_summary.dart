//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'episode_summary.g.dart';

/// Compact episode representation for lists.
///
/// Properties:
/// * [pid] - Type-prefixed ULID.
/// * [mediaType] 
/// * [title] - Display title.
/// * [artist] - Primary display artist / author / show name.
/// * [album] - Album / series / podcast title, when applicable.
/// * [artistPid] - The artist entity behind `artist`, so a client can group and link by identity rather than by display text — two artists with the same name are two entities, and one artist spelled two ways is still one. Absent when the item has no artist entity. For an audiobook this is its author. 
/// * [albumPid] - The album entity behind `album`, for the same reason. Tracks only: a podcast episode and an audiobook are not album members, and their `album` is a series or show title with no album entity behind it. Absent when the track belongs to no album. 
/// * [trackNumber] - Track position within its disc (music). On the summary row rather than only on the detail because a listing is where it is needed: an album's items page arrives in the library's own stable order, and this plus `discNumber` is what a client sorts a release back into. Absent when the item carries none. 
/// * [discNumber] - Disc number within a multi-disc release (music). Absent for a single-disc release and for anything that is not a track. 
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
@BuiltValue(instantiable: false)
abstract class EpisodeSummary implements ItemSummary {
  /// Feed-declared explicit flag.
  @BuiltValueField(wireName: r'explicit')
  bool? get explicit;

  /// Feed-declared episode type (`full`, `trailer`, `bonus`). Open set; treat unknown values like `full`. 
  @BuiltValueField(wireName: r'episodeType')
  String? get episodeType;

  /// Why the last fetch attempt failed (`fetchState` is `failed`). Retrying the fetch endpoint re-queues it. 
  @BuiltValueField(wireName: r'fetchError')
  String? get fetchError;

  /// Present while a server-side fetch is queued or after one failed: `queued` or `failed`. Absent otherwise. Open set; treat unknown values as `queued`. 
  @BuiltValueField(wireName: r'fetchState')
  String? get fetchState;

  /// Publication time. When the feed declares none, the server substitutes the time it first saw the episode, so ordering and paging stay total. 
  @BuiltValueField(wireName: r'publishedAt')
  DateTime get publishedAt;

  /// The show this episode belongs to.
  @BuiltValueField(wireName: r'showPid')
  String get showPid;

  /// Season number, when the feed declares one.
  @BuiltValueField(wireName: r'season')
  int? get season;

  /// Episode number, when the feed declares one.
  @BuiltValueField(wireName: r'episodeNumber')
  int? get episodeNumber;

  /// Whether the audio is on the server. Playback needs the fetch first: play-info for a not-yet-fetched episode answers `conflict`, and the episode fetch endpoint queues the download. 
  @BuiltValueField(wireName: r'downloaded')
  bool get downloaded;

  /// Whether a transcript is available.
  @BuiltValueField(wireName: r'hasTranscript')
  bool? get hasTranscript;

  @BuiltValueSerializer(custom: true)
  static Serializer<EpisodeSummary> get serializer => _$EpisodeSummarySerializer();
}

class _$EpisodeSummarySerializer implements PrimitiveSerializer<EpisodeSummary> {
  @override
  final Iterable<Type> types = const [EpisodeSummary];

  @override
  final String wireName = r'EpisodeSummary';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EpisodeSummary object, {
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
    if (object.trackNumber != null) {
      yield r'trackNumber';
      yield serializers.serialize(
        object.trackNumber,
        specifiedType: const FullType(int),
      );
    }
    yield r'publishedAt';
    yield serializers.serialize(
      object.publishedAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    if (object.album != null) {
      yield r'album';
      yield serializers.serialize(
        object.album,
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
    if (object.albumPid != null) {
      yield r'albumPid';
      yield serializers.serialize(
        object.albumPid,
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
    if (object.artUrl != null) {
      yield r'artUrl';
      yield serializers.serialize(
        object.artUrl,
        specifiedType: const FullType(String),
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
    if (object.discNumber != null) {
      yield r'discNumber';
      yield serializers.serialize(
        object.discNumber,
        specifiedType: const FullType(int),
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
    if (object.artistPid != null) {
      yield r'artistPid';
      yield serializers.serialize(
        object.artistPid,
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
    EpisodeSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  EpisodeSummary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($EpisodeSummary)) as $EpisodeSummary;
  }
}

/// a concrete implementation of [EpisodeSummary], since [EpisodeSummary] is not instantiable
@BuiltValue(instantiable: true)
abstract class $EpisodeSummary implements EpisodeSummary, Built<$EpisodeSummary, $EpisodeSummaryBuilder> {
  $EpisodeSummary._();

  factory $EpisodeSummary([void Function($EpisodeSummaryBuilder)? updates]) = _$$EpisodeSummary;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($EpisodeSummaryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$EpisodeSummary> get serializer => _$$EpisodeSummarySerializer();
}

class _$$EpisodeSummarySerializer implements PrimitiveSerializer<$EpisodeSummary> {
  @override
  final Iterable<Type> types = const [$EpisodeSummary, _$$EpisodeSummary];

  @override
  final String wireName = r'$EpisodeSummary';

  @override
  Object serialize(
    Serializers serializers,
    $EpisodeSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(EpisodeSummary))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EpisodeSummaryBuilder result,
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
        case r'trackNumber':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.trackNumber = valueDes;
          break;
        case r'publishedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.publishedAt = valueDes;
          break;
        case r'artist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artist = valueDes;
          break;
        case r'album':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.album = valueDes;
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
        case r'albumPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.albumPid = valueDes;
          break;
        case r'hasTranscript':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasTranscript = valueDes;
          break;
        case r'artUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artUrl = valueDes;
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
        case r'discNumber':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.discNumber = valueDes;
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
        case r'artistPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artistPid = valueDes;
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
  $EpisodeSummary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $EpisodeSummaryBuilder();
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

