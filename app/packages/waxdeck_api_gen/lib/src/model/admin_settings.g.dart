// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_settings.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AdminSettings extends AdminSettings {
  @override
  final bool signupEnabled;
  @override
  final bool readOnly;
  @override
  final int backupKeepCount;
  @override
  final int backupKeepBytes;

  factory _$AdminSettings([void Function(AdminSettingsBuilder)? updates]) =>
      (AdminSettingsBuilder()..update(updates))._build();

  _$AdminSettings._({
    required this.signupEnabled,
    required this.readOnly,
    required this.backupKeepCount,
    required this.backupKeepBytes,
  }) : super._();
  @override
  AdminSettings rebuild(void Function(AdminSettingsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AdminSettingsBuilder toBuilder() => AdminSettingsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AdminSettings &&
        signupEnabled == other.signupEnabled &&
        readOnly == other.readOnly &&
        backupKeepCount == other.backupKeepCount &&
        backupKeepBytes == other.backupKeepBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, signupEnabled.hashCode);
    _$hash = $jc(_$hash, readOnly.hashCode);
    _$hash = $jc(_$hash, backupKeepCount.hashCode);
    _$hash = $jc(_$hash, backupKeepBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AdminSettings')
          ..add('signupEnabled', signupEnabled)
          ..add('readOnly', readOnly)
          ..add('backupKeepCount', backupKeepCount)
          ..add('backupKeepBytes', backupKeepBytes))
        .toString();
  }
}

class AdminSettingsBuilder
    implements Builder<AdminSettings, AdminSettingsBuilder> {
  _$AdminSettings? _$v;

  bool? _signupEnabled;
  bool? get signupEnabled => _$this._signupEnabled;
  set signupEnabled(bool? signupEnabled) =>
      _$this._signupEnabled = signupEnabled;

  bool? _readOnly;
  bool? get readOnly => _$this._readOnly;
  set readOnly(bool? readOnly) => _$this._readOnly = readOnly;

  int? _backupKeepCount;
  int? get backupKeepCount => _$this._backupKeepCount;
  set backupKeepCount(int? backupKeepCount) =>
      _$this._backupKeepCount = backupKeepCount;

  int? _backupKeepBytes;
  int? get backupKeepBytes => _$this._backupKeepBytes;
  set backupKeepBytes(int? backupKeepBytes) =>
      _$this._backupKeepBytes = backupKeepBytes;

  AdminSettingsBuilder() {
    AdminSettings._defaults(this);
  }

  AdminSettingsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _signupEnabled = $v.signupEnabled;
      _readOnly = $v.readOnly;
      _backupKeepCount = $v.backupKeepCount;
      _backupKeepBytes = $v.backupKeepBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AdminSettings other) {
    _$v = other as _$AdminSettings;
  }

  @override
  void update(void Function(AdminSettingsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AdminSettings build() => _build();

  _$AdminSettings _build() {
    final _$result =
        _$v ??
        _$AdminSettings._(
          signupEnabled: BuiltValueNullFieldError.checkNotNull(
            signupEnabled,
            r'AdminSettings',
            'signupEnabled',
          ),
          readOnly: BuiltValueNullFieldError.checkNotNull(
            readOnly,
            r'AdminSettings',
            'readOnly',
          ),
          backupKeepCount: BuiltValueNullFieldError.checkNotNull(
            backupKeepCount,
            r'AdminSettings',
            'backupKeepCount',
          ),
          backupKeepBytes: BuiltValueNullFieldError.checkNotNull(
            backupKeepBytes,
            r'AdminSettings',
            'backupKeepBytes',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
