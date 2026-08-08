// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prefs.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PrefsThemeEnum _$prefsThemeEnum_system = const PrefsThemeEnum._('system');
const PrefsThemeEnum _$prefsThemeEnum_dark = const PrefsThemeEnum._('dark');
const PrefsThemeEnum _$prefsThemeEnum_light = const PrefsThemeEnum._('light');
const PrefsThemeEnum _$prefsThemeEnum_oled = const PrefsThemeEnum._('oled');

PrefsThemeEnum _$prefsThemeEnumValueOf(String name) {
  switch (name) {
    case 'system':
      return _$prefsThemeEnum_system;
    case 'dark':
      return _$prefsThemeEnum_dark;
    case 'light':
      return _$prefsThemeEnum_light;
    case 'oled':
      return _$prefsThemeEnum_oled;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PrefsThemeEnum> _$prefsThemeEnumValues =
    BuiltSet<PrefsThemeEnum>(const <PrefsThemeEnum>[
      _$prefsThemeEnum_system,
      _$prefsThemeEnum_dark,
      _$prefsThemeEnum_light,
      _$prefsThemeEnum_oled,
    ]);

const PrefsBrowseSortsEnum _$prefsBrowseSortsEnum_count =
    const PrefsBrowseSortsEnum._('count');
const PrefsBrowseSortsEnum _$prefsBrowseSortsEnum_label =
    const PrefsBrowseSortsEnum._('label');

PrefsBrowseSortsEnum _$prefsBrowseSortsEnumValueOf(String name) {
  switch (name) {
    case 'count':
      return _$prefsBrowseSortsEnum_count;
    case 'label':
      return _$prefsBrowseSortsEnum_label;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PrefsBrowseSortsEnum> _$prefsBrowseSortsEnumValues =
    BuiltSet<PrefsBrowseSortsEnum>(const <PrefsBrowseSortsEnum>[
      _$prefsBrowseSortsEnum_count,
      _$prefsBrowseSortsEnum_label,
    ]);

Serializer<PrefsThemeEnum> _$prefsThemeEnumSerializer =
    _$PrefsThemeEnumSerializer();
Serializer<PrefsBrowseSortsEnum> _$prefsBrowseSortsEnumSerializer =
    _$PrefsBrowseSortsEnumSerializer();

class _$PrefsThemeEnumSerializer
    implements PrimitiveSerializer<PrefsThemeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'system': 'system',
    'dark': 'dark',
    'light': 'light',
    'oled': 'oled',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'system': 'system',
    'dark': 'dark',
    'light': 'light',
    'oled': 'oled',
  };

  @override
  final Iterable<Type> types = const <Type>[PrefsThemeEnum];
  @override
  final String wireName = 'PrefsThemeEnum';

  @override
  Object serialize(
    Serializers serializers,
    PrefsThemeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  PrefsThemeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => PrefsThemeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$PrefsBrowseSortsEnumSerializer
    implements PrimitiveSerializer<PrefsBrowseSortsEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'count': 'count',
    'label': 'label',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'count': 'count',
    'label': 'label',
  };

  @override
  final Iterable<Type> types = const <Type>[PrefsBrowseSortsEnum];
  @override
  final String wireName = 'PrefsBrowseSortsEnum';

  @override
  Object serialize(
    Serializers serializers,
    PrefsBrowseSortsEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  PrefsBrowseSortsEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => PrefsBrowseSortsEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$Prefs extends Prefs {
  @override
  final String? timezone;
  @override
  final String? locale;
  @override
  final PrefsThemeEnum? theme;
  @override
  final bool? sharedStatsOptOut;
  @override
  final BuiltList<String>? radioFavorites;
  @override
  final BuiltList<String>? pinned;
  @override
  final double? crossfadeSeconds;
  @override
  final bool? replayGain;
  @override
  final bool? browseShowUnknown;
  @override
  final BuiltMap<String, PrefsBrowseSortsEnum>? browseSorts;
  @override
  final bool? autoplay;
  @override
  final bool? radioScrobbleOptOut;

  factory _$Prefs([void Function(PrefsBuilder)? updates]) =>
      (PrefsBuilder()..update(updates))._build();

  _$Prefs._({
    this.timezone,
    this.locale,
    this.theme,
    this.sharedStatsOptOut,
    this.radioFavorites,
    this.pinned,
    this.crossfadeSeconds,
    this.replayGain,
    this.browseShowUnknown,
    this.browseSorts,
    this.autoplay,
    this.radioScrobbleOptOut,
  }) : super._();
  @override
  Prefs rebuild(void Function(PrefsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PrefsBuilder toBuilder() => PrefsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Prefs &&
        timezone == other.timezone &&
        locale == other.locale &&
        theme == other.theme &&
        sharedStatsOptOut == other.sharedStatsOptOut &&
        radioFavorites == other.radioFavorites &&
        pinned == other.pinned &&
        crossfadeSeconds == other.crossfadeSeconds &&
        replayGain == other.replayGain &&
        browseShowUnknown == other.browseShowUnknown &&
        browseSorts == other.browseSorts &&
        autoplay == other.autoplay &&
        radioScrobbleOptOut == other.radioScrobbleOptOut;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, timezone.hashCode);
    _$hash = $jc(_$hash, locale.hashCode);
    _$hash = $jc(_$hash, theme.hashCode);
    _$hash = $jc(_$hash, sharedStatsOptOut.hashCode);
    _$hash = $jc(_$hash, radioFavorites.hashCode);
    _$hash = $jc(_$hash, pinned.hashCode);
    _$hash = $jc(_$hash, crossfadeSeconds.hashCode);
    _$hash = $jc(_$hash, replayGain.hashCode);
    _$hash = $jc(_$hash, browseShowUnknown.hashCode);
    _$hash = $jc(_$hash, browseSorts.hashCode);
    _$hash = $jc(_$hash, autoplay.hashCode);
    _$hash = $jc(_$hash, radioScrobbleOptOut.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Prefs')
          ..add('timezone', timezone)
          ..add('locale', locale)
          ..add('theme', theme)
          ..add('sharedStatsOptOut', sharedStatsOptOut)
          ..add('radioFavorites', radioFavorites)
          ..add('pinned', pinned)
          ..add('crossfadeSeconds', crossfadeSeconds)
          ..add('replayGain', replayGain)
          ..add('browseShowUnknown', browseShowUnknown)
          ..add('browseSorts', browseSorts)
          ..add('autoplay', autoplay)
          ..add('radioScrobbleOptOut', radioScrobbleOptOut))
        .toString();
  }
}

class PrefsBuilder implements Builder<Prefs, PrefsBuilder> {
  _$Prefs? _$v;

  String? _timezone;
  String? get timezone => _$this._timezone;
  set timezone(String? timezone) => _$this._timezone = timezone;

  String? _locale;
  String? get locale => _$this._locale;
  set locale(String? locale) => _$this._locale = locale;

  PrefsThemeEnum? _theme;
  PrefsThemeEnum? get theme => _$this._theme;
  set theme(PrefsThemeEnum? theme) => _$this._theme = theme;

  bool? _sharedStatsOptOut;
  bool? get sharedStatsOptOut => _$this._sharedStatsOptOut;
  set sharedStatsOptOut(bool? sharedStatsOptOut) =>
      _$this._sharedStatsOptOut = sharedStatsOptOut;

  ListBuilder<String>? _radioFavorites;
  ListBuilder<String> get radioFavorites =>
      _$this._radioFavorites ??= ListBuilder<String>();
  set radioFavorites(ListBuilder<String>? radioFavorites) =>
      _$this._radioFavorites = radioFavorites;

  ListBuilder<String>? _pinned;
  ListBuilder<String> get pinned => _$this._pinned ??= ListBuilder<String>();
  set pinned(ListBuilder<String>? pinned) => _$this._pinned = pinned;

  double? _crossfadeSeconds;
  double? get crossfadeSeconds => _$this._crossfadeSeconds;
  set crossfadeSeconds(double? crossfadeSeconds) =>
      _$this._crossfadeSeconds = crossfadeSeconds;

  bool? _replayGain;
  bool? get replayGain => _$this._replayGain;
  set replayGain(bool? replayGain) => _$this._replayGain = replayGain;

  bool? _browseShowUnknown;
  bool? get browseShowUnknown => _$this._browseShowUnknown;
  set browseShowUnknown(bool? browseShowUnknown) =>
      _$this._browseShowUnknown = browseShowUnknown;

  MapBuilder<String, PrefsBrowseSortsEnum>? _browseSorts;
  MapBuilder<String, PrefsBrowseSortsEnum> get browseSorts =>
      _$this._browseSorts ??= MapBuilder<String, PrefsBrowseSortsEnum>();
  set browseSorts(MapBuilder<String, PrefsBrowseSortsEnum>? browseSorts) =>
      _$this._browseSorts = browseSorts;

  bool? _autoplay;
  bool? get autoplay => _$this._autoplay;
  set autoplay(bool? autoplay) => _$this._autoplay = autoplay;

  bool? _radioScrobbleOptOut;
  bool? get radioScrobbleOptOut => _$this._radioScrobbleOptOut;
  set radioScrobbleOptOut(bool? radioScrobbleOptOut) =>
      _$this._radioScrobbleOptOut = radioScrobbleOptOut;

  PrefsBuilder() {
    Prefs._defaults(this);
  }

  PrefsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _timezone = $v.timezone;
      _locale = $v.locale;
      _theme = $v.theme;
      _sharedStatsOptOut = $v.sharedStatsOptOut;
      _radioFavorites = $v.radioFavorites?.toBuilder();
      _pinned = $v.pinned?.toBuilder();
      _crossfadeSeconds = $v.crossfadeSeconds;
      _replayGain = $v.replayGain;
      _browseShowUnknown = $v.browseShowUnknown;
      _browseSorts = $v.browseSorts?.toBuilder();
      _autoplay = $v.autoplay;
      _radioScrobbleOptOut = $v.radioScrobbleOptOut;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Prefs other) {
    _$v = other as _$Prefs;
  }

  @override
  void update(void Function(PrefsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Prefs build() => _build();

  _$Prefs _build() {
    _$Prefs _$result;
    try {
      _$result =
          _$v ??
          _$Prefs._(
            timezone: timezone,
            locale: locale,
            theme: theme,
            sharedStatsOptOut: sharedStatsOptOut,
            radioFavorites: _radioFavorites?.build(),
            pinned: _pinned?.build(),
            crossfadeSeconds: crossfadeSeconds,
            replayGain: replayGain,
            browseShowUnknown: browseShowUnknown,
            browseSorts: _browseSorts?.build(),
            autoplay: autoplay,
            radioScrobbleOptOut: radioScrobbleOptOut,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'radioFavorites';
        _radioFavorites?.build();
        _$failedField = 'pinned';
        _pinned?.build();

        _$failedField = 'browseSorts';
        _browseSorts?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'Prefs', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
