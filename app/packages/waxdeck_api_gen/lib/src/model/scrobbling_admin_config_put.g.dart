// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scrobbling_admin_config_put.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ScrobblingAdminConfigPut extends ScrobblingAdminConfigPut {
  @override
  final String lastfmApiKey;
  @override
  final String lastfmSecret;

  factory _$ScrobblingAdminConfigPut([
    void Function(ScrobblingAdminConfigPutBuilder)? updates,
  ]) => (ScrobblingAdminConfigPutBuilder()..update(updates))._build();

  _$ScrobblingAdminConfigPut._({
    required this.lastfmApiKey,
    required this.lastfmSecret,
  }) : super._();
  @override
  ScrobblingAdminConfigPut rebuild(
    void Function(ScrobblingAdminConfigPutBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ScrobblingAdminConfigPutBuilder toBuilder() =>
      ScrobblingAdminConfigPutBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScrobblingAdminConfigPut &&
        lastfmApiKey == other.lastfmApiKey &&
        lastfmSecret == other.lastfmSecret;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, lastfmApiKey.hashCode);
    _$hash = $jc(_$hash, lastfmSecret.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ScrobblingAdminConfigPut')
          ..add('lastfmApiKey', lastfmApiKey)
          ..add('lastfmSecret', lastfmSecret))
        .toString();
  }
}

class ScrobblingAdminConfigPutBuilder
    implements
        Builder<ScrobblingAdminConfigPut, ScrobblingAdminConfigPutBuilder> {
  _$ScrobblingAdminConfigPut? _$v;

  String? _lastfmApiKey;
  String? get lastfmApiKey => _$this._lastfmApiKey;
  set lastfmApiKey(String? lastfmApiKey) => _$this._lastfmApiKey = lastfmApiKey;

  String? _lastfmSecret;
  String? get lastfmSecret => _$this._lastfmSecret;
  set lastfmSecret(String? lastfmSecret) => _$this._lastfmSecret = lastfmSecret;

  ScrobblingAdminConfigPutBuilder() {
    ScrobblingAdminConfigPut._defaults(this);
  }

  ScrobblingAdminConfigPutBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _lastfmApiKey = $v.lastfmApiKey;
      _lastfmSecret = $v.lastfmSecret;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScrobblingAdminConfigPut other) {
    _$v = other as _$ScrobblingAdminConfigPut;
  }

  @override
  void update(void Function(ScrobblingAdminConfigPutBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ScrobblingAdminConfigPut build() => _build();

  _$ScrobblingAdminConfigPut _build() {
    final _$result =
        _$v ??
        _$ScrobblingAdminConfigPut._(
          lastfmApiKey: BuiltValueNullFieldError.checkNotNull(
            lastfmApiKey,
            r'ScrobblingAdminConfigPut',
            'lastfmApiKey',
          ),
          lastfmSecret: BuiltValueNullFieldError.checkNotNull(
            lastfmSecret,
            r'ScrobblingAdminConfigPut',
            'lastfmSecret',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
