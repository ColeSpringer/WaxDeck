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

Serializer<PrefsThemeEnum> _$prefsThemeEnumSerializer =
    _$PrefsThemeEnumSerializer();

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

class _$Prefs extends Prefs {
  @override
  final String? timezone;
  @override
  final String? locale;
  @override
  final PrefsThemeEnum? theme;
  @override
  final bool? sharedStatsOptOut;

  factory _$Prefs([void Function(PrefsBuilder)? updates]) =>
      (PrefsBuilder()..update(updates))._build();

  _$Prefs._({this.timezone, this.locale, this.theme, this.sharedStatsOptOut})
    : super._();
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
        sharedStatsOptOut == other.sharedStatsOptOut;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, timezone.hashCode);
    _$hash = $jc(_$hash, locale.hashCode);
    _$hash = $jc(_$hash, theme.hashCode);
    _$hash = $jc(_$hash, sharedStatsOptOut.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Prefs')
          ..add('timezone', timezone)
          ..add('locale', locale)
          ..add('theme', theme)
          ..add('sharedStatsOptOut', sharedStatsOptOut))
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
    final _$result =
        _$v ??
        _$Prefs._(
          timezone: timezone,
          locale: locale,
          theme: theme,
          sharedStatsOptOut: sharedStatsOptOut,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
