//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/podcast_funding.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/feed_person.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'podcast_show.g.dart';

/// One globally cataloged show. Show privacy is a global, sticky property: a show becomes private when it is first subscribed with credentials or when any subscriber ever marks their subscription private, and it never becomes public again. For a private show, `feedUrl` is omitted from every response for every user, and the show is excluded from every user's OPML export: tokenized feed URLs and credentials are secrets. Privacy protects the URL and credentials only, never the show's existence or content, which any user with visibility into the podcast library can browse and play. 
///
/// Properties:
/// * [pid] - Show PID.
/// * [title] - Show title.
/// * [author] - Show author or channel name.
/// * [descriptionHtml] - Show description as sanitized HTML (server-side allowlist; safe to render directly). 
/// * [feedUrl] - The feed URL. Omitted for private feeds.
/// * [link] - The show's website, when the feed declares one.
/// * [sourceType] - Where the show comes from: `rss`, `youtube` (a channel or playlist through the acquisition bridge), or `manual` (a local-folder show). Open set; treat unknown values like `rss`. 
/// * [artUrl] - Origin-relative URL of the show's artwork endpoint.
/// * [episodeCount] - Number of cataloged episodes.
/// * [lastPublishedAt] - Publication time of the newest cataloged episode.
/// * [refreshDisabled] - True when scheduled refresh is suspended after repeated feed failures. A successful manual refresh clears it. 
/// * [explicit] - Feed-declared explicit flag for the whole show. Episodes carry their own flag, which wins where the feed sets both. 
/// * [funding] 
/// * [medium] - The show's declared medium from its feed's `<podcast:medium>` tag, lowercased (`podcast`, `music`, `audiobook`, ...). Open set; absent when the feed declares none. 
/// * [persons] - Show-level `<podcast:person>` credits (hosts, guests, and other roles). Populated on the show detail read only; absent on subscription list rows. 
@BuiltValue()
abstract class PodcastShow implements Built<PodcastShow, PodcastShowBuilder> {
  /// Show PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Show title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Show author or channel name.
  @BuiltValueField(wireName: r'author')
  String? get author;

  /// Show description as sanitized HTML (server-side allowlist; safe to render directly). 
  @BuiltValueField(wireName: r'descriptionHtml')
  String? get descriptionHtml;

  /// The feed URL. Omitted for private feeds.
  @BuiltValueField(wireName: r'feedUrl')
  String? get feedUrl;

  /// The show's website, when the feed declares one.
  @BuiltValueField(wireName: r'link')
  String? get link;

  /// Where the show comes from: `rss`, `youtube` (a channel or playlist through the acquisition bridge), or `manual` (a local-folder show). Open set; treat unknown values like `rss`. 
  @BuiltValueField(wireName: r'sourceType')
  String get sourceType;

  /// Origin-relative URL of the show's artwork endpoint.
  @BuiltValueField(wireName: r'artUrl')
  String? get artUrl;

  /// Number of cataloged episodes.
  @BuiltValueField(wireName: r'episodeCount')
  int? get episodeCount;

  /// Publication time of the newest cataloged episode.
  @BuiltValueField(wireName: r'lastPublishedAt')
  DateTime? get lastPublishedAt;

  /// True when scheduled refresh is suspended after repeated feed failures. A successful manual refresh clears it. 
  @BuiltValueField(wireName: r'refreshDisabled')
  bool? get refreshDisabled;

  /// Feed-declared explicit flag for the whole show. Episodes carry their own flag, which wins where the feed sets both. 
  @BuiltValueField(wireName: r'explicit')
  bool? get explicit;

  @BuiltValueField(wireName: r'funding')
  PodcastFunding? get funding;

  /// The show's declared medium from its feed's `<podcast:medium>` tag, lowercased (`podcast`, `music`, `audiobook`, ...). Open set; absent when the feed declares none. 
  @BuiltValueField(wireName: r'medium')
  String? get medium;

  /// Show-level `<podcast:person>` credits (hosts, guests, and other roles). Populated on the show detail read only; absent on subscription list rows. 
  @BuiltValueField(wireName: r'persons')
  BuiltList<FeedPerson>? get persons;

  PodcastShow._();

  factory PodcastShow([void updates(PodcastShowBuilder b)]) = _$PodcastShow;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PodcastShowBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PodcastShow> get serializer => _$PodcastShowSerializer();
}

class _$PodcastShowSerializer implements PrimitiveSerializer<PodcastShow> {
  @override
  final Iterable<Type> types = const [PodcastShow, _$PodcastShow];

  @override
  final String wireName = r'PodcastShow';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PodcastShow object, {
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
    if (object.author != null) {
      yield r'author';
      yield serializers.serialize(
        object.author,
        specifiedType: const FullType(String),
      );
    }
    if (object.descriptionHtml != null) {
      yield r'descriptionHtml';
      yield serializers.serialize(
        object.descriptionHtml,
        specifiedType: const FullType(String),
      );
    }
    if (object.feedUrl != null) {
      yield r'feedUrl';
      yield serializers.serialize(
        object.feedUrl,
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
    yield r'sourceType';
    yield serializers.serialize(
      object.sourceType,
      specifiedType: const FullType(String),
    );
    if (object.artUrl != null) {
      yield r'artUrl';
      yield serializers.serialize(
        object.artUrl,
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
    if (object.lastPublishedAt != null) {
      yield r'lastPublishedAt';
      yield serializers.serialize(
        object.lastPublishedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.refreshDisabled != null) {
      yield r'refreshDisabled';
      yield serializers.serialize(
        object.refreshDisabled,
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
    if (object.funding != null) {
      yield r'funding';
      yield serializers.serialize(
        object.funding,
        specifiedType: const FullType(PodcastFunding),
      );
    }
    if (object.medium != null) {
      yield r'medium';
      yield serializers.serialize(
        object.medium,
        specifiedType: const FullType(String),
      );
    }
    if (object.persons != null) {
      yield r'persons';
      yield serializers.serialize(
        object.persons,
        specifiedType: const FullType(BuiltList, [FullType(FeedPerson)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PodcastShow object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PodcastShowBuilder result,
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
        case r'author':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.author = valueDes;
          break;
        case r'descriptionHtml':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.descriptionHtml = valueDes;
          break;
        case r'feedUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.feedUrl = valueDes;
          break;
        case r'link':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.link = valueDes;
          break;
        case r'sourceType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceType = valueDes;
          break;
        case r'artUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artUrl = valueDes;
          break;
        case r'episodeCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.episodeCount = valueDes;
          break;
        case r'lastPublishedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastPublishedAt = valueDes;
          break;
        case r'refreshDisabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.refreshDisabled = valueDes;
          break;
        case r'explicit':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.explicit = valueDes;
          break;
        case r'funding':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PodcastFunding),
          ) as PodcastFunding;
          result.funding.replace(valueDes);
          break;
        case r'medium':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.medium = valueDes;
          break;
        case r'persons':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(FeedPerson)]),
          ) as BuiltList<FeedPerson>;
          result.persons.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PodcastShow deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PodcastShowBuilder();
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

