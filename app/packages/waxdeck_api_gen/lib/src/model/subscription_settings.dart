//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/episode_filter.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'subscription_settings.g.dart';

/// The calling user's per-subscription settings. All fields are optional; an absent field means the server default. `PUT` replaces the whole object. 
///
/// Properties:
/// * [retentionKeep] - Keep the newest N downloaded episode files for this user; 0 means keep all. Null (or absent) means the server default, which is keep-all unless the administrator configured otherwise. The effective policy for a show is the most generous union across its subscribers, and removing a file never removes playback history (archive, not delete). 
/// * [autoDownload] - Fetch new episodes to the server automatically as the feed publishes them. `autoDownloadFilter` narrows which ones. 
/// * [autoDownloadFilter] 
/// * [folder] - Folder path for organizing subscriptions, as segments joined by `/` (round-trips through OPML outline nesting). 
/// * [private] - Mark the show private (see the show schema: privacy is global and sticky, hiding the feed URL everywhere and keeping the show out of every OPML export). Set automatically when subscribing with credentials. Setting this back to false does not un-private a show. 
/// * [speed] - Playback speed override for this show.
/// * [trimSilence] - Trim mapped silence spans when playing this show.
/// * [voiceBoost] - Apply spoken-word loudness normalization for this show.
/// * [skipIntroSeconds] - Seconds to skip at the start of every episode.
/// * [skipOutroSeconds] - Seconds to skip at the end of every episode.
@BuiltValue()
abstract class SubscriptionSettings implements Built<SubscriptionSettings, SubscriptionSettingsBuilder> {
  /// Keep the newest N downloaded episode files for this user; 0 means keep all. Null (or absent) means the server default, which is keep-all unless the administrator configured otherwise. The effective policy for a show is the most generous union across its subscribers, and removing a file never removes playback history (archive, not delete). 
  @BuiltValueField(wireName: r'retentionKeep')
  int? get retentionKeep;

  /// Fetch new episodes to the server automatically as the feed publishes them. `autoDownloadFilter` narrows which ones. 
  @BuiltValueField(wireName: r'autoDownload')
  bool? get autoDownload;

  @BuiltValueField(wireName: r'autoDownloadFilter')
  EpisodeFilter? get autoDownloadFilter;

  /// Folder path for organizing subscriptions, as segments joined by `/` (round-trips through OPML outline nesting). 
  @BuiltValueField(wireName: r'folder')
  String? get folder;

  /// Mark the show private (see the show schema: privacy is global and sticky, hiding the feed URL everywhere and keeping the show out of every OPML export). Set automatically when subscribing with credentials. Setting this back to false does not un-private a show. 
  @BuiltValueField(wireName: r'private')
  bool? get private;

  /// Playback speed override for this show.
  @BuiltValueField(wireName: r'speed')
  double? get speed;

  /// Trim mapped silence spans when playing this show.
  @BuiltValueField(wireName: r'trimSilence')
  bool? get trimSilence;

  /// Apply spoken-word loudness normalization for this show.
  @BuiltValueField(wireName: r'voiceBoost')
  bool? get voiceBoost;

  /// Seconds to skip at the start of every episode.
  @BuiltValueField(wireName: r'skipIntroSeconds')
  int? get skipIntroSeconds;

  /// Seconds to skip at the end of every episode.
  @BuiltValueField(wireName: r'skipOutroSeconds')
  int? get skipOutroSeconds;

  SubscriptionSettings._();

  factory SubscriptionSettings([void updates(SubscriptionSettingsBuilder b)]) = _$SubscriptionSettings;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SubscriptionSettingsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SubscriptionSettings> get serializer => _$SubscriptionSettingsSerializer();
}

class _$SubscriptionSettingsSerializer implements PrimitiveSerializer<SubscriptionSettings> {
  @override
  final Iterable<Type> types = const [SubscriptionSettings, _$SubscriptionSettings];

  @override
  final String wireName = r'SubscriptionSettings';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SubscriptionSettings object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.retentionKeep != null) {
      yield r'retentionKeep';
      yield serializers.serialize(
        object.retentionKeep,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.autoDownload != null) {
      yield r'autoDownload';
      yield serializers.serialize(
        object.autoDownload,
        specifiedType: const FullType(bool),
      );
    }
    if (object.autoDownloadFilter != null) {
      yield r'autoDownloadFilter';
      yield serializers.serialize(
        object.autoDownloadFilter,
        specifiedType: const FullType(EpisodeFilter),
      );
    }
    if (object.folder != null) {
      yield r'folder';
      yield serializers.serialize(
        object.folder,
        specifiedType: const FullType(String),
      );
    }
    if (object.private != null) {
      yield r'private';
      yield serializers.serialize(
        object.private,
        specifiedType: const FullType(bool),
      );
    }
    if (object.speed != null) {
      yield r'speed';
      yield serializers.serialize(
        object.speed,
        specifiedType: const FullType(double),
      );
    }
    if (object.trimSilence != null) {
      yield r'trimSilence';
      yield serializers.serialize(
        object.trimSilence,
        specifiedType: const FullType(bool),
      );
    }
    if (object.voiceBoost != null) {
      yield r'voiceBoost';
      yield serializers.serialize(
        object.voiceBoost,
        specifiedType: const FullType(bool),
      );
    }
    if (object.skipIntroSeconds != null) {
      yield r'skipIntroSeconds';
      yield serializers.serialize(
        object.skipIntroSeconds,
        specifiedType: const FullType(int),
      );
    }
    if (object.skipOutroSeconds != null) {
      yield r'skipOutroSeconds';
      yield serializers.serialize(
        object.skipOutroSeconds,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SubscriptionSettings object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SubscriptionSettingsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'retentionKeep':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.retentionKeep = valueDes;
          break;
        case r'autoDownload':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.autoDownload = valueDes;
          break;
        case r'autoDownloadFilter':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EpisodeFilter),
          ) as EpisodeFilter;
          result.autoDownloadFilter.replace(valueDes);
          break;
        case r'folder':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.folder = valueDes;
          break;
        case r'private':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.private = valueDes;
          break;
        case r'speed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.speed = valueDes;
          break;
        case r'trimSilence':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.trimSilence = valueDes;
          break;
        case r'voiceBoost':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.voiceBoost = valueDes;
          break;
        case r'skipIntroSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.skipIntroSeconds = valueDes;
          break;
        case r'skipOutroSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.skipOutroSeconds = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SubscriptionSettings deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SubscriptionSettingsBuilder();
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

