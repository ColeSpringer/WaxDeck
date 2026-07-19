// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_settings.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookSettings extends BookSettings {
  @override
  final double? speed;
  @override
  final bool? voiceBoost;
  @override
  final bool? trimSilence;

  factory _$BookSettings([void Function(BookSettingsBuilder)? updates]) =>
      (BookSettingsBuilder()..update(updates))._build();

  _$BookSettings._({this.speed, this.voiceBoost, this.trimSilence}) : super._();
  @override
  BookSettings rebuild(void Function(BookSettingsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookSettingsBuilder toBuilder() => BookSettingsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookSettings &&
        speed == other.speed &&
        voiceBoost == other.voiceBoost &&
        trimSilence == other.trimSilence;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, speed.hashCode);
    _$hash = $jc(_$hash, voiceBoost.hashCode);
    _$hash = $jc(_$hash, trimSilence.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookSettings')
          ..add('speed', speed)
          ..add('voiceBoost', voiceBoost)
          ..add('trimSilence', trimSilence))
        .toString();
  }
}

class BookSettingsBuilder
    implements Builder<BookSettings, BookSettingsBuilder> {
  _$BookSettings? _$v;

  double? _speed;
  double? get speed => _$this._speed;
  set speed(double? speed) => _$this._speed = speed;

  bool? _voiceBoost;
  bool? get voiceBoost => _$this._voiceBoost;
  set voiceBoost(bool? voiceBoost) => _$this._voiceBoost = voiceBoost;

  bool? _trimSilence;
  bool? get trimSilence => _$this._trimSilence;
  set trimSilence(bool? trimSilence) => _$this._trimSilence = trimSilence;

  BookSettingsBuilder() {
    BookSettings._defaults(this);
  }

  BookSettingsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _speed = $v.speed;
      _voiceBoost = $v.voiceBoost;
      _trimSilence = $v.trimSilence;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookSettings other) {
    _$v = other as _$BookSettings;
  }

  @override
  void update(void Function(BookSettingsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookSettings build() => _build();

  _$BookSettings _build() {
    final _$result =
        _$v ??
        _$BookSettings._(
          speed: speed,
          voiceBoost: voiceBoost,
          trimSilence: trimSilence,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
