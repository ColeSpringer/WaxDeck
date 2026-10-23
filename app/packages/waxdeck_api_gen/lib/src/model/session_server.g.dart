// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_server.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SessionServer extends SessionServer {
  @override
  final bool readOnly;

  factory _$SessionServer([void Function(SessionServerBuilder)? updates]) =>
      (SessionServerBuilder()..update(updates))._build();

  _$SessionServer._({required this.readOnly}) : super._();
  @override
  SessionServer rebuild(void Function(SessionServerBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SessionServerBuilder toBuilder() => SessionServerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SessionServer && readOnly == other.readOnly;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, readOnly.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'SessionServer',
    )..add('readOnly', readOnly)).toString();
  }
}

class SessionServerBuilder
    implements Builder<SessionServer, SessionServerBuilder> {
  _$SessionServer? _$v;

  bool? _readOnly;
  bool? get readOnly => _$this._readOnly;
  set readOnly(bool? readOnly) => _$this._readOnly = readOnly;

  SessionServerBuilder() {
    SessionServer._defaults(this);
  }

  SessionServerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _readOnly = $v.readOnly;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SessionServer other) {
    _$v = other as _$SessionServer;
  }

  @override
  void update(void Function(SessionServerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SessionServer build() => _build();

  _$SessionServer _build() {
    final _$result =
        _$v ??
        _$SessionServer._(
          readOnly: BuiltValueNullFieldError.checkNotNull(
            readOnly,
            r'SessionServer',
            'readOnly',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
