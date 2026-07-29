// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subscription_settings.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SubscriptionSettings extends SubscriptionSettings {
  @override
  final int? retentionKeep;
  @override
  final bool? autoDownload;
  @override
  final EpisodeFilter? autoDownloadFilter;
  @override
  final String? folder;
  @override
  final bool? private;
  @override
  final double? speed;
  @override
  final bool? trimSilence;
  @override
  final bool? voiceBoost;
  @override
  final int? skipIntroSeconds;
  @override
  final int? skipOutroSeconds;

  factory _$SubscriptionSettings([
    void Function(SubscriptionSettingsBuilder)? updates,
  ]) => (SubscriptionSettingsBuilder()..update(updates))._build();

  _$SubscriptionSettings._({
    this.retentionKeep,
    this.autoDownload,
    this.autoDownloadFilter,
    this.folder,
    this.private,
    this.speed,
    this.trimSilence,
    this.voiceBoost,
    this.skipIntroSeconds,
    this.skipOutroSeconds,
  }) : super._();
  @override
  SubscriptionSettings rebuild(
    void Function(SubscriptionSettingsBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  SubscriptionSettingsBuilder toBuilder() =>
      SubscriptionSettingsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SubscriptionSettings &&
        retentionKeep == other.retentionKeep &&
        autoDownload == other.autoDownload &&
        autoDownloadFilter == other.autoDownloadFilter &&
        folder == other.folder &&
        private == other.private &&
        speed == other.speed &&
        trimSilence == other.trimSilence &&
        voiceBoost == other.voiceBoost &&
        skipIntroSeconds == other.skipIntroSeconds &&
        skipOutroSeconds == other.skipOutroSeconds;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, retentionKeep.hashCode);
    _$hash = $jc(_$hash, autoDownload.hashCode);
    _$hash = $jc(_$hash, autoDownloadFilter.hashCode);
    _$hash = $jc(_$hash, folder.hashCode);
    _$hash = $jc(_$hash, private.hashCode);
    _$hash = $jc(_$hash, speed.hashCode);
    _$hash = $jc(_$hash, trimSilence.hashCode);
    _$hash = $jc(_$hash, voiceBoost.hashCode);
    _$hash = $jc(_$hash, skipIntroSeconds.hashCode);
    _$hash = $jc(_$hash, skipOutroSeconds.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SubscriptionSettings')
          ..add('retentionKeep', retentionKeep)
          ..add('autoDownload', autoDownload)
          ..add('autoDownloadFilter', autoDownloadFilter)
          ..add('folder', folder)
          ..add('private', private)
          ..add('speed', speed)
          ..add('trimSilence', trimSilence)
          ..add('voiceBoost', voiceBoost)
          ..add('skipIntroSeconds', skipIntroSeconds)
          ..add('skipOutroSeconds', skipOutroSeconds))
        .toString();
  }
}

class SubscriptionSettingsBuilder
    implements Builder<SubscriptionSettings, SubscriptionSettingsBuilder> {
  _$SubscriptionSettings? _$v;

  int? _retentionKeep;
  int? get retentionKeep => _$this._retentionKeep;
  set retentionKeep(int? retentionKeep) =>
      _$this._retentionKeep = retentionKeep;

  bool? _autoDownload;
  bool? get autoDownload => _$this._autoDownload;
  set autoDownload(bool? autoDownload) => _$this._autoDownload = autoDownload;

  EpisodeFilterBuilder? _autoDownloadFilter;
  EpisodeFilterBuilder get autoDownloadFilter =>
      _$this._autoDownloadFilter ??= EpisodeFilterBuilder();
  set autoDownloadFilter(EpisodeFilterBuilder? autoDownloadFilter) =>
      _$this._autoDownloadFilter = autoDownloadFilter;

  String? _folder;
  String? get folder => _$this._folder;
  set folder(String? folder) => _$this._folder = folder;

  bool? _private;
  bool? get private => _$this._private;
  set private(bool? private) => _$this._private = private;

  double? _speed;
  double? get speed => _$this._speed;
  set speed(double? speed) => _$this._speed = speed;

  bool? _trimSilence;
  bool? get trimSilence => _$this._trimSilence;
  set trimSilence(bool? trimSilence) => _$this._trimSilence = trimSilence;

  bool? _voiceBoost;
  bool? get voiceBoost => _$this._voiceBoost;
  set voiceBoost(bool? voiceBoost) => _$this._voiceBoost = voiceBoost;

  int? _skipIntroSeconds;
  int? get skipIntroSeconds => _$this._skipIntroSeconds;
  set skipIntroSeconds(int? skipIntroSeconds) =>
      _$this._skipIntroSeconds = skipIntroSeconds;

  int? _skipOutroSeconds;
  int? get skipOutroSeconds => _$this._skipOutroSeconds;
  set skipOutroSeconds(int? skipOutroSeconds) =>
      _$this._skipOutroSeconds = skipOutroSeconds;

  SubscriptionSettingsBuilder() {
    SubscriptionSettings._defaults(this);
  }

  SubscriptionSettingsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _retentionKeep = $v.retentionKeep;
      _autoDownload = $v.autoDownload;
      _autoDownloadFilter = $v.autoDownloadFilter?.toBuilder();
      _folder = $v.folder;
      _private = $v.private;
      _speed = $v.speed;
      _trimSilence = $v.trimSilence;
      _voiceBoost = $v.voiceBoost;
      _skipIntroSeconds = $v.skipIntroSeconds;
      _skipOutroSeconds = $v.skipOutroSeconds;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SubscriptionSettings other) {
    _$v = other as _$SubscriptionSettings;
  }

  @override
  void update(void Function(SubscriptionSettingsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SubscriptionSettings build() => _build();

  _$SubscriptionSettings _build() {
    _$SubscriptionSettings _$result;
    try {
      _$result =
          _$v ??
          _$SubscriptionSettings._(
            retentionKeep: retentionKeep,
            autoDownload: autoDownload,
            autoDownloadFilter: _autoDownloadFilter?.build(),
            folder: folder,
            private: private,
            speed: speed,
            trimSilence: trimSilence,
            voiceBoost: voiceBoost,
            skipIntroSeconds: skipIntroSeconds,
            skipOutroSeconds: skipOutroSeconds,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'autoDownloadFilter';
        _autoDownloadFilter?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SubscriptionSettings',
          _$failedField,
          e.toString(),
        );
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
