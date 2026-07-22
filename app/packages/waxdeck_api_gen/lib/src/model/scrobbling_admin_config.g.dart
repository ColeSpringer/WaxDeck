// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scrobbling_admin_config.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ScrobblingAdminConfig extends ScrobblingAdminConfig {
  @override
  final bool lastfmConfigured;
  @override
  final String lastfmSource;
  @override
  final String? lastfmApiKey;
  @override
  final bool lastfmSecretSet;

  factory _$ScrobblingAdminConfig([
    void Function(ScrobblingAdminConfigBuilder)? updates,
  ]) => (ScrobblingAdminConfigBuilder()..update(updates))._build();

  _$ScrobblingAdminConfig._({
    required this.lastfmConfigured,
    required this.lastfmSource,
    this.lastfmApiKey,
    required this.lastfmSecretSet,
  }) : super._();
  @override
  ScrobblingAdminConfig rebuild(
    void Function(ScrobblingAdminConfigBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ScrobblingAdminConfigBuilder toBuilder() =>
      ScrobblingAdminConfigBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScrobblingAdminConfig &&
        lastfmConfigured == other.lastfmConfigured &&
        lastfmSource == other.lastfmSource &&
        lastfmApiKey == other.lastfmApiKey &&
        lastfmSecretSet == other.lastfmSecretSet;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, lastfmConfigured.hashCode);
    _$hash = $jc(_$hash, lastfmSource.hashCode);
    _$hash = $jc(_$hash, lastfmApiKey.hashCode);
    _$hash = $jc(_$hash, lastfmSecretSet.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ScrobblingAdminConfig')
          ..add('lastfmConfigured', lastfmConfigured)
          ..add('lastfmSource', lastfmSource)
          ..add('lastfmApiKey', lastfmApiKey)
          ..add('lastfmSecretSet', lastfmSecretSet))
        .toString();
  }
}

class ScrobblingAdminConfigBuilder
    implements Builder<ScrobblingAdminConfig, ScrobblingAdminConfigBuilder> {
  _$ScrobblingAdminConfig? _$v;

  bool? _lastfmConfigured;
  bool? get lastfmConfigured => _$this._lastfmConfigured;
  set lastfmConfigured(bool? lastfmConfigured) =>
      _$this._lastfmConfigured = lastfmConfigured;

  String? _lastfmSource;
  String? get lastfmSource => _$this._lastfmSource;
  set lastfmSource(String? lastfmSource) => _$this._lastfmSource = lastfmSource;

  String? _lastfmApiKey;
  String? get lastfmApiKey => _$this._lastfmApiKey;
  set lastfmApiKey(String? lastfmApiKey) => _$this._lastfmApiKey = lastfmApiKey;

  bool? _lastfmSecretSet;
  bool? get lastfmSecretSet => _$this._lastfmSecretSet;
  set lastfmSecretSet(bool? lastfmSecretSet) =>
      _$this._lastfmSecretSet = lastfmSecretSet;

  ScrobblingAdminConfigBuilder() {
    ScrobblingAdminConfig._defaults(this);
  }

  ScrobblingAdminConfigBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _lastfmConfigured = $v.lastfmConfigured;
      _lastfmSource = $v.lastfmSource;
      _lastfmApiKey = $v.lastfmApiKey;
      _lastfmSecretSet = $v.lastfmSecretSet;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScrobblingAdminConfig other) {
    _$v = other as _$ScrobblingAdminConfig;
  }

  @override
  void update(void Function(ScrobblingAdminConfigBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ScrobblingAdminConfig build() => _build();

  _$ScrobblingAdminConfig _build() {
    final _$result =
        _$v ??
        _$ScrobblingAdminConfig._(
          lastfmConfigured: BuiltValueNullFieldError.checkNotNull(
            lastfmConfigured,
            r'ScrobblingAdminConfig',
            'lastfmConfigured',
          ),
          lastfmSource: BuiltValueNullFieldError.checkNotNull(
            lastfmSource,
            r'ScrobblingAdminConfig',
            'lastfmSource',
          ),
          lastfmApiKey: lastfmApiKey,
          lastfmSecretSet: BuiltValueNullFieldError.checkNotNull(
            lastfmSecretSet,
            r'ScrobblingAdminConfig',
            'lastfmSecretSet',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
