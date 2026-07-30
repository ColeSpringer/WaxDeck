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

