// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UserUpdate extends UserUpdate {
  @override
  final String? displayName;
  @override
  final BuiltList<Role>? roles;
  @override
  final bool? disabled;
  @override
  final LibraryAccess? libraryAccess;

  factory _$UserUpdate([void Function(UserUpdateBuilder)? updates]) =>
      (UserUpdateBuilder()..update(updates))._build();

  _$UserUpdate._({
    this.displayName,
    this.roles,
    this.disabled,
    this.libraryAccess,
  }) : super._();
  @override
  UserUpdate rebuild(void Function(UserUpdateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UserUpdateBuilder toBuilder() => UserUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UserUpdate &&
        displayName == other.displayName &&
        roles == other.roles &&
        disabled == other.disabled &&
        libraryAccess == other.libraryAccess;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, roles.hashCode);
    _$hash = $jc(_$hash, disabled.hashCode);
    _$hash = $jc(_$hash, libraryAccess.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UserUpdate')
          ..add('displayName', displayName)
          ..add('roles', roles)
          ..add('disabled', disabled)
          ..add('libraryAccess', libraryAccess))
        .toString();
  }
}

class UserUpdateBuilder implements Builder<UserUpdate, UserUpdateBuilder> {
  _$UserUpdate? _$v;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  ListBuilder<Role>? _roles;
  ListBuilder<Role> get roles => _$this._roles ??= ListBuilder<Role>();
  set roles(ListBuilder<Role>? roles) => _$this._roles = roles;

  bool? _disabled;
  bool? get disabled => _$this._disabled;
  set disabled(bool? disabled) => _$this._disabled = disabled;

  LibraryAccessBuilder? _libraryAccess;
  LibraryAccessBuilder get libraryAccess =>
      _$this._libraryAccess ??= LibraryAccessBuilder();
  set libraryAccess(LibraryAccessBuilder? libraryAccess) =>
      _$this._libraryAccess = libraryAccess;

  UserUpdateBuilder() {
    UserUpdate._defaults(this);
  }

  UserUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _displayName = $v.displayName;
      _roles = $v.roles?.toBuilder();
      _disabled = $v.disabled;
      _libraryAccess = $v.libraryAccess?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UserUpdate other) {
    _$v = other as _$UserUpdate;
  }

  @override
  void update(void Function(UserUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UserUpdate build() => _build();

  _$UserUpdate _build() {
    _$UserUpdate _$result;
    try {
      _$result =
          _$v ??
          _$UserUpdate._(
            displayName: displayName,
            roles: _roles?.build(),
            disabled: disabled,
            libraryAccess: _libraryAccess?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'roles';
        _roles?.build();

        _$failedField = 'libraryAccess';
        _libraryAccess?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'UserUpdate',
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
