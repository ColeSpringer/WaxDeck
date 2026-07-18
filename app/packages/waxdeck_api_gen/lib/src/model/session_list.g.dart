// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SessionList extends SessionList {
  @override
  final BuiltList<DeviceSession> sessions;

  factory _$SessionList([void Function(SessionListBuilder)? updates]) =>
      (SessionListBuilder()..update(updates))._build();

  _$SessionList._({required this.sessions}) : super._();
  @override
  SessionList rebuild(void Function(SessionListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SessionListBuilder toBuilder() => SessionListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SessionList && sessions == other.sessions;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sessions.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'SessionList',
    )..add('sessions', sessions)).toString();
  }
}

class SessionListBuilder implements Builder<SessionList, SessionListBuilder> {
  _$SessionList? _$v;

  ListBuilder<DeviceSession>? _sessions;
  ListBuilder<DeviceSession> get sessions =>
      _$this._sessions ??= ListBuilder<DeviceSession>();
  set sessions(ListBuilder<DeviceSession>? sessions) =>
      _$this._sessions = sessions;

  SessionListBuilder() {
    SessionList._defaults(this);
  }

  SessionListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sessions = $v.sessions.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SessionList other) {
    _$v = other as _$SessionList;
  }

  @override
  void update(void Function(SessionListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SessionList build() => _build();

  _$SessionList _build() {
    _$SessionList _$result;
    try {
      _$result = _$v ?? _$SessionList._(sessions: sessions.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'sessions';
        sessions.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SessionList',
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
