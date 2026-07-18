// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'password_change.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PasswordChange extends PasswordChange {
  @override
  final String? currentPassword;
  @override
  final String newPassword;

  factory _$PasswordChange([void Function(PasswordChangeBuilder)? updates]) =>
      (PasswordChangeBuilder()..update(updates))._build();

  _$PasswordChange._({this.currentPassword, required this.newPassword})
    : super._();
  @override
  PasswordChange rebuild(void Function(PasswordChangeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PasswordChangeBuilder toBuilder() => PasswordChangeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PasswordChange &&
        currentPassword == other.currentPassword &&
        newPassword == other.newPassword;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, currentPassword.hashCode);
    _$hash = $jc(_$hash, newPassword.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PasswordChange')
          ..add('currentPassword', currentPassword)
          ..add('newPassword', newPassword))
        .toString();
  }
}

class PasswordChangeBuilder
    implements Builder<PasswordChange, PasswordChangeBuilder> {
  _$PasswordChange? _$v;

  String? _currentPassword;
  String? get currentPassword => _$this._currentPassword;
  set currentPassword(String? currentPassword) =>
      _$this._currentPassword = currentPassword;

  String? _newPassword;
  String? get newPassword => _$this._newPassword;
  set newPassword(String? newPassword) => _$this._newPassword = newPassword;

  PasswordChangeBuilder() {
    PasswordChange._defaults(this);
  }

  PasswordChangeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _currentPassword = $v.currentPassword;
      _newPassword = $v.newPassword;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PasswordChange other) {
    _$v = other as _$PasswordChange;
  }

  @override
  void update(void Function(PasswordChangeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PasswordChange build() => _build();

  _$PasswordChange _build() {
    final _$result =
        _$v ??
        _$PasswordChange._(
          currentPassword: currentPassword,
          newPassword: BuiltValueNullFieldError.checkNotNull(
            newPassword,
            r'PasswordChange',
            'newPassword',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
