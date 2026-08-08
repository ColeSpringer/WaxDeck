//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'prefs.g.dart';

/// Per-user preferences that sync across clients. All fields are optional; unset fields are absent and clients apply their own defaults. Unknown fields are rejected. 
///
/// Properties:
/// * [timezone] - IANA timezone name (for example `Europe/Amsterdam`). Drives streaks, heatmaps, and other calendar-bucketed statistics. 
/// * [locale] - Preferred BCP 47 locale tag (for example `en-US`).
/// * [theme] - Preferred app theme.
/// * [sharedStatsOptOut] - Leave the server-wide aggregate stats (the server year in review). Household members are enrolled by default; opting out removes this user's listening from every server-wide figure. Personal stats are unaffected. 
/// * [radioFavorites] - Radio stations this user has pinned, in the order the dial presents them. The station library itself is shared by every account, so this is the one piece of per-user station state there is: which of the household's stations are *yours*.  Ordered, and the order is the client's to set - new pins go on the end, so a dial does not reshuffle under a thumb. Entries are station PIDs (`rs-...`) and are not resolved on write: a station deleted by another household member leaves its pid here, and a client renders only the pids it can still find, because failing a whole preference write over one departed station would be worse than a dial one slot shorter.  Capped at 64, which is a bound on the document rather than on the feature: clients present about a dozen, and that cap is theirs. A client presenting fewer than the document holds must still write back what it did not draw - the cap belongs to the dial, not to the list.  Stored in the canonical upper-case form the pattern above declares, whatever case a write used, so a pin always names the station the server named. Absent when nothing is pinned: unpinning everything drops the field rather than storing `[]`, and nothing reads a default set of pins out of an absent list, so absent and empty are one answer on the way back. 
/// * [pinned] - What this user has pinned to home, in the order the shelf presents them. The same shape and the same rules as `radioFavorites`, for the same reason: a pin is about the listener rather than the machine they made it on, so it follows the account.  Ordered, and the order is the client's to set - new pins go on the end. Entries are entity PIDs and are not resolved on write: an album another household member deleted leaves its pid here, and a client draws only the pids it can still resolve, because failing a whole preference write over one departed release would be worse than a shelf one card shorter. Resolve them with `POST /library/entities`, which silently drops what it cannot answer for.  Albums (`al-`), artists (`ar-`), release groups (`rg-`), playlists (`pl-`), podcast shows (`pc-`), and books (`bk-`) may be pinned. Radio stations may not: the dial is already radio's pin surface, and two pin gestures for one station would be two places to unpin it from. Tracks and episodes may not either: a card opens a surface, and a kept set of tracks is a playlist - which pins.  Capped at 64, a bound on the document rather than on the feature. Stored in the canonical upper-case form the pattern declares, whatever case a write used. Absent when nothing is pinned: unpinning everything drops the field rather than storing `[]`. 
/// * [crossfadeSeconds] - Equal-power crossfade applied at every seam of a queue the server renders as one stream, in seconds. Zero or absent is a gapless butt join.  Here rather than in a client's own per-device storage because the server is what applies it: a cast session is re-rendered server-side on every queue edit, shuffle, and repeat reload, and those arrive over the control socket carrying no client state at all. A per-device value would reach the first load and none of the reloads, so the queue would change how it sounds halfway through. Local playback does not read this yet, which is why clients label it for casting. 
/// * [replayGain] - Level a server-rendered queue to a common loudness. The gain is derived from the measured loudness the analyze pass stores per file and applied once to the whole stream, so a queue whose files were never analyzed plays unlevelled whatever this says.  Same reason as `crossfadeSeconds` for living on the account rather than on the device, and the same labeling: nothing local reads it yet. 
/// * [browseShowUnknown] - Whether a browse index draws the bucket for the items a dimension is absent from (`[No Genre]`, `[Non-Album]`). Absent means shown. A presentation preference, not a server filter: the bucket stays enumerated and drillable whatever this says. 
/// * [browseSorts] - The order each browse index opens in, keyed by the dimension name `GET /library/browse` spells (`genre`, `artist`, `credit-artist`, `album-artist`, `album`, `release-group`, `year`, `kind`, or a `tag.<KEY>` dimension); values are that endpoint's `sort` values. Sparse: a dimension with no entry opens in the client's own default, so a write must merge rather than replace. Capped at 32 entries. 
/// * [autoplay] - Whether playback may start with no gesture behind it - a queue another device hands over through Connect. Absent means allowed. Off means the client loads what it was asked for and waits to be tapped, which is what a browser enforces on the web build anyway. It does not gate a gesture made somewhere other than the screen: a browse-tree tap on a head unit still plays. 
/// * [radioScrobbleOptOut] - Stop scrobbling radio. Listeners with a scrobble connection have their radio segments reported by default, which is right for a music station whose stream titles are honest and wrong for a talk station whose titles happen to parse. Opting out silences radio only; library listening is unaffected. 
@BuiltValue()
abstract class Prefs implements Built<Prefs, PrefsBuilder> {
  /// IANA timezone name (for example `Europe/Amsterdam`). Drives streaks, heatmaps, and other calendar-bucketed statistics. 
  @BuiltValueField(wireName: r'timezone')
  String? get timezone;

  /// Preferred BCP 47 locale tag (for example `en-US`).
  @BuiltValueField(wireName: r'locale')
  String? get locale;

  /// Preferred app theme.
  @BuiltValueField(wireName: r'theme')
  PrefsThemeEnum? get theme;
  // enum themeEnum {  system,  dark,  light,  oled,  };

  /// Leave the server-wide aggregate stats (the server year in review). Household members are enrolled by default; opting out removes this user's listening from every server-wide figure. Personal stats are unaffected. 
  @BuiltValueField(wireName: r'sharedStatsOptOut')
  bool? get sharedStatsOptOut;

  /// Radio stations this user has pinned, in the order the dial presents them. The station library itself is shared by every account, so this is the one piece of per-user station state there is: which of the household's stations are *yours*.  Ordered, and the order is the client's to set - new pins go on the end, so a dial does not reshuffle under a thumb. Entries are station PIDs (`rs-...`) and are not resolved on write: a station deleted by another household member leaves its pid here, and a client renders only the pids it can still find, because failing a whole preference write over one departed station would be worse than a dial one slot shorter.  Capped at 64, which is a bound on the document rather than on the feature: clients present about a dozen, and that cap is theirs. A client presenting fewer than the document holds must still write back what it did not draw - the cap belongs to the dial, not to the list.  Stored in the canonical upper-case form the pattern above declares, whatever case a write used, so a pin always names the station the server named. Absent when nothing is pinned: unpinning everything drops the field rather than storing `[]`, and nothing reads a default set of pins out of an absent list, so absent and empty are one answer on the way back. 
  @BuiltValueField(wireName: r'radioFavorites')
  BuiltList<String>? get radioFavorites;

  /// What this user has pinned to home, in the order the shelf presents them. The same shape and the same rules as `radioFavorites`, for the same reason: a pin is about the listener rather than the machine they made it on, so it follows the account.  Ordered, and the order is the client's to set - new pins go on the end. Entries are entity PIDs and are not resolved on write: an album another household member deleted leaves its pid here, and a client draws only the pids it can still resolve, because failing a whole preference write over one departed release would be worse than a shelf one card shorter. Resolve them with `POST /library/entities`, which silently drops what it cannot answer for.  Albums (`al-`), artists (`ar-`), release groups (`rg-`), playlists (`pl-`), podcast shows (`pc-`), and books (`bk-`) may be pinned. Radio stations may not: the dial is already radio's pin surface, and two pin gestures for one station would be two places to unpin it from. Tracks and episodes may not either: a card opens a surface, and a kept set of tracks is a playlist - which pins.  Capped at 64, a bound on the document rather than on the feature. Stored in the canonical upper-case form the pattern declares, whatever case a write used. Absent when nothing is pinned: unpinning everything drops the field rather than storing `[]`. 
  @BuiltValueField(wireName: r'pinned')
  BuiltList<String>? get pinned;

  /// Equal-power crossfade applied at every seam of a queue the server renders as one stream, in seconds. Zero or absent is a gapless butt join.  Here rather than in a client's own per-device storage because the server is what applies it: a cast session is re-rendered server-side on every queue edit, shuffle, and repeat reload, and those arrive over the control socket carrying no client state at all. A per-device value would reach the first load and none of the reloads, so the queue would change how it sounds halfway through. Local playback does not read this yet, which is why clients label it for casting. 
  @BuiltValueField(wireName: r'crossfadeSeconds')
  double? get crossfadeSeconds;

  /// Level a server-rendered queue to a common loudness. The gain is derived from the measured loudness the analyze pass stores per file and applied once to the whole stream, so a queue whose files were never analyzed plays unlevelled whatever this says.  Same reason as `crossfadeSeconds` for living on the account rather than on the device, and the same labeling: nothing local reads it yet. 
  @BuiltValueField(wireName: r'replayGain')
  bool? get replayGain;

  /// Whether a browse index draws the bucket for the items a dimension is absent from (`[No Genre]`, `[Non-Album]`). Absent means shown. A presentation preference, not a server filter: the bucket stays enumerated and drillable whatever this says. 
  @BuiltValueField(wireName: r'browseShowUnknown')
  bool? get browseShowUnknown;

  /// The order each browse index opens in, keyed by the dimension name `GET /library/browse` spells (`genre`, `artist`, `credit-artist`, `album-artist`, `album`, `release-group`, `year`, `kind`, or a `tag.<KEY>` dimension); values are that endpoint's `sort` values. Sparse: a dimension with no entry opens in the client's own default, so a write must merge rather than replace. Capped at 32 entries. 
  @BuiltValueField(wireName: r'browseSorts')
  BuiltMap<String, PrefsBrowseSortsEnum>? get browseSorts;
  // enum browseSortsEnum {  count,  label,  };

  /// Whether playback may start with no gesture behind it - a queue another device hands over through Connect. Absent means allowed. Off means the client loads what it was asked for and waits to be tapped, which is what a browser enforces on the web build anyway. It does not gate a gesture made somewhere other than the screen: a browse-tree tap on a head unit still plays. 
  @BuiltValueField(wireName: r'autoplay')
  bool? get autoplay;

  /// Stop scrobbling radio. Listeners with a scrobble connection have their radio segments reported by default, which is right for a music station whose stream titles are honest and wrong for a talk station whose titles happen to parse. Opting out silences radio only; library listening is unaffected. 
  @BuiltValueField(wireName: r'radioScrobbleOptOut')
  bool? get radioScrobbleOptOut;

  Prefs._();

  factory Prefs([void updates(PrefsBuilder b)]) = _$Prefs;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PrefsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Prefs> get serializer => _$PrefsSerializer();
}

class _$PrefsSerializer implements PrimitiveSerializer<Prefs> {
  @override
  final Iterable<Type> types = const [Prefs, _$Prefs];

  @override
  final String wireName = r'Prefs';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Prefs object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.timezone != null) {
      yield r'timezone';
      yield serializers.serialize(
        object.timezone,
        specifiedType: const FullType(String),
      );
    }
    if (object.locale != null) {
      yield r'locale';
      yield serializers.serialize(
        object.locale,
        specifiedType: const FullType(String),
      );
    }
    if (object.theme != null) {
      yield r'theme';
      yield serializers.serialize(
        object.theme,
        specifiedType: const FullType(PrefsThemeEnum),
      );
    }
    if (object.sharedStatsOptOut != null) {
      yield r'sharedStatsOptOut';
      yield serializers.serialize(
        object.sharedStatsOptOut,
        specifiedType: const FullType(bool),
      );
    }
    if (object.radioFavorites != null) {
      yield r'radioFavorites';
      yield serializers.serialize(
        object.radioFavorites,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.pinned != null) {
      yield r'pinned';
      yield serializers.serialize(
        object.pinned,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.crossfadeSeconds != null) {
      yield r'crossfadeSeconds';
      yield serializers.serialize(
        object.crossfadeSeconds,
        specifiedType: const FullType(double),
      );
    }
    if (object.replayGain != null) {
      yield r'replayGain';
      yield serializers.serialize(
        object.replayGain,
        specifiedType: const FullType(bool),
      );
    }
    if (object.browseShowUnknown != null) {
      yield r'browseShowUnknown';
      yield serializers.serialize(
        object.browseShowUnknown,
        specifiedType: const FullType(bool),
      );
    }
    if (object.browseSorts != null) {
      yield r'browseSorts';
      yield serializers.serialize(
        object.browseSorts,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType(PrefsBrowseSortsEnum)]),
      );
    }
    if (object.autoplay != null) {
      yield r'autoplay';
      yield serializers.serialize(
        object.autoplay,
        specifiedType: const FullType(bool),
      );
    }
    if (object.radioScrobbleOptOut != null) {
      yield r'radioScrobbleOptOut';
      yield serializers.serialize(
        object.radioScrobbleOptOut,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Prefs object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PrefsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'timezone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.timezone = valueDes;
          break;
        case r'locale':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.locale = valueDes;
          break;
        case r'theme':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PrefsThemeEnum),
          ) as PrefsThemeEnum;
          result.theme = valueDes;
          break;
        case r'sharedStatsOptOut':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.sharedStatsOptOut = valueDes;
          break;
        case r'radioFavorites':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.radioFavorites.replace(valueDes);
          break;
        case r'pinned':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.pinned.replace(valueDes);
          break;
        case r'crossfadeSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.crossfadeSeconds = valueDes;
          break;
        case r'replayGain':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.replayGain = valueDes;
          break;
        case r'browseShowUnknown':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.browseShowUnknown = valueDes;
          break;
        case r'browseSorts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(PrefsBrowseSortsEnum)]),
          ) as BuiltMap<String, PrefsBrowseSortsEnum>;
          result.browseSorts.replace(valueDes);
          break;
        case r'autoplay':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.autoplay = valueDes;
          break;
        case r'radioScrobbleOptOut':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.radioScrobbleOptOut = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Prefs deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PrefsBuilder();
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

class PrefsThemeEnum extends EnumClass {

  /// Preferred app theme.
  @BuiltValueEnumConst(wireName: r'system')
  static const PrefsThemeEnum system = _$prefsThemeEnum_system;
  /// Preferred app theme.
  @BuiltValueEnumConst(wireName: r'dark')
  static const PrefsThemeEnum dark = _$prefsThemeEnum_dark;
  /// Preferred app theme.
  @BuiltValueEnumConst(wireName: r'light')
  static const PrefsThemeEnum light = _$prefsThemeEnum_light;
  /// Preferred app theme.
  @BuiltValueEnumConst(wireName: r'oled')
  static const PrefsThemeEnum oled = _$prefsThemeEnum_oled;

  static Serializer<PrefsThemeEnum> get serializer => _$prefsThemeEnumSerializer;

  const PrefsThemeEnum._(String name): super(name);

  static BuiltSet<PrefsThemeEnum> get values => _$prefsThemeEnumValues;
  static PrefsThemeEnum valueOf(String name) => _$prefsThemeEnumValueOf(name);
}

class PrefsBrowseSortsEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'count')
  static const PrefsBrowseSortsEnum count = _$prefsBrowseSortsEnum_count;
  @BuiltValueEnumConst(wireName: r'label')
  static const PrefsBrowseSortsEnum label = _$prefsBrowseSortsEnum_label;

  static Serializer<PrefsBrowseSortsEnum> get serializer => _$prefsBrowseSortsEnumSerializer;

  const PrefsBrowseSortsEnum._(String name): super(name);

  static BuiltSet<PrefsBrowseSortsEnum> get values => _$prefsBrowseSortsEnumValues;
  static PrefsBrowseSortsEnum valueOf(String name) => _$prefsBrowseSortsEnumValueOf(name);
}

