// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_rename.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SessionRename extends SessionRename {
  @override
  final String deviceName;

  factory _$SessionRename([void Function(SessionRenameBuilder)? updates]) =>
      (SessionRenameBuilder()..update(updates))._build();

  _$SessionRename._({required this.deviceName}) : super._();
  @override
  SessionRename rebuild(void Function(SessionRenameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SessionRenameBuilder toBuilder() => SessionRenameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SessionRename && deviceName == other.deviceName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, deviceName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'SessionRename',
    )..add('deviceName', deviceName)).toString();
  }
}

class SessionRenameBuilder
    implements Builder<SessionRename, SessionRenameBuilder> {
  _$SessionRename? _$v;

  String? _deviceName;
  String? get deviceName => _$this._deviceName;
  set deviceName(String? deviceName) => _$this._deviceName = deviceName;

  SessionRenameBuilder() {
    SessionRename._defaults(this);
  }

  SessionRenameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _deviceName = $v.deviceName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SessionRename other) {
    _$v = other as _$SessionRename;
  }

  @override
  void update(void Function(SessionRenameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SessionRename build() => _build();

  _$SessionRename _build() {
    final _$result =
        _$v ??
        _$SessionRename._(
          deviceName: BuiltValueNullFieldError.checkNotNull(
            deviceName,
            r'SessionRename',
            'deviceName',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
