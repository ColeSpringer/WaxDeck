// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scrobbler.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Scrobbler extends Scrobbler {
  @override
  final String service;
  @override
  final bool available;
  @override
  final bool connected;
  @override
  final String? username;
  @override
  final String? apiUrl;
  @override
  final DateTime? lastSuccessAt;
  @override
  final String? lastError;
  @override
  final DateTime? lastErrorAt;

  factory _$Scrobbler([void Function(ScrobblerBuilder)? updates]) =>
      (ScrobblerBuilder()..update(updates))._build();

  _$Scrobbler._({
    required this.service,
    required this.available,
    required this.connected,
    this.username,
    this.apiUrl,
    this.lastSuccessAt,
    this.lastError,
    this.lastErrorAt,
  }) : super._();
  @override
  Scrobbler rebuild(void Function(ScrobblerBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScrobblerBuilder toBuilder() => ScrobblerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Scrobbler &&
        service == other.service &&
        available == other.available &&
        connected == other.connected &&
        username == other.username &&
        apiUrl == other.apiUrl &&
        lastSuccessAt == other.lastSuccessAt &&
        lastError == other.lastError &&
        lastErrorAt == other.lastErrorAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, service.hashCode);
    _$hash = $jc(_$hash, available.hashCode);
    _$hash = $jc(_$hash, connected.hashCode);
    _$hash = $jc(_$hash, username.hashCode);
    _$hash = $jc(_$hash, apiUrl.hashCode);
    _$hash = $jc(_$hash, lastSuccessAt.hashCode);
    _$hash = $jc(_$hash, lastError.hashCode);
    _$hash = $jc(_$hash, lastErrorAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Scrobbler')
          ..add('service', service)
          ..add('available', available)
          ..add('connected', connected)
          ..add('username', username)
          ..add('apiUrl', apiUrl)
          ..add('lastSuccessAt', lastSuccessAt)
          ..add('lastError', lastError)
          ..add('lastErrorAt', lastErrorAt))
        .toString();
  }
}

class ScrobblerBuilder implements Builder<Scrobbler, ScrobblerBuilder> {
  _$Scrobbler? _$v;

  String? _service;
  String? get service => _$this._service;
  set service(String? service) => _$this._service = service;

  bool? _available;
  bool? get available => _$this._available;
  set available(bool? available) => _$this._available = available;

  bool? _connected;
  bool? get connected => _$this._connected;
  set connected(bool? connected) => _$this._connected = connected;

  String? _username;
  String? get username => _$this._username;
  set username(String? username) => _$this._username = username;

  String? _apiUrl;
  String? get apiUrl => _$this._apiUrl;
  set apiUrl(String? apiUrl) => _$this._apiUrl = apiUrl;

  DateTime? _lastSuccessAt;
  DateTime? get lastSuccessAt => _$this._lastSuccessAt;
  set lastSuccessAt(DateTime? lastSuccessAt) =>
      _$this._lastSuccessAt = lastSuccessAt;

  String? _lastError;
  String? get lastError => _$this._lastError;
  set lastError(String? lastError) => _$this._lastError = lastError;

  DateTime? _lastErrorAt;
  DateTime? get lastErrorAt => _$this._lastErrorAt;
  set lastErrorAt(DateTime? lastErrorAt) => _$this._lastErrorAt = lastErrorAt;

  ScrobblerBuilder() {
    Scrobbler._defaults(this);
  }

  ScrobblerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _service = $v.service;
      _available = $v.available;
      _connected = $v.connected;
      _username = $v.username;
      _apiUrl = $v.apiUrl;
      _lastSuccessAt = $v.lastSuccessAt;
      _lastError = $v.lastError;
      _lastErrorAt = $v.lastErrorAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Scrobbler other) {
    _$v = other as _$Scrobbler;
  }

  @override
  void update(void Function(ScrobblerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Scrobbler build() => _build();

  _$Scrobbler _build() {
    final _$result =
        _$v ??
        _$Scrobbler._(
          service: BuiltValueNullFieldError.checkNotNull(
            service,
            r'Scrobbler',
            'service',
          ),
          available: BuiltValueNullFieldError.checkNotNull(
            available,
            r'Scrobbler',
            'available',
          ),
          connected: BuiltValueNullFieldError.checkNotNull(
            connected,
            r'Scrobbler',
            'connected',
          ),
          username: username,
          apiUrl: apiUrl,
          lastSuccessAt: lastSuccessAt,
          lastError: lastError,
          lastErrorAt: lastErrorAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
