// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

abstract mixin class UserBuilder {
  void replace(User other);
  void update(void Function(UserBuilder) updates);
  String? get id;
  set id(String? id);

  String? get username;
  set username(String? username);

  String? get displayName;
  set displayName(String? displayName);

  ListBuilder<String> get roles;
  set roles(ListBuilder<String>? roles);

  bool? get uploadEnabled;
  set uploadEnabled(bool? uploadEnabled);

  bool? get managePodcasts;
  set managePodcasts(bool? managePodcasts);

  bool? get delete;
  set delete(bool? delete);
}

class _$$User extends $User {
  @override
  final String id;
  @override
  final String username;
  @override
  final String? displayName;
  @override
  final BuiltList<String> roles;
  @override
  final bool uploadEnabled;
  @override
  final bool? managePodcasts;
  @override
  final bool? delete;

  factory _$$User([void Function($UserBuilder)? updates]) =>
      ($UserBuilder()..update(updates))._build();

  _$$User._({
    required this.id,
    required this.username,
    this.displayName,
    required this.roles,
    required this.uploadEnabled,
    this.managePodcasts,
    this.delete,
  }) : super._();
  @override
  $User rebuild(void Function($UserBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  $UserBuilder toBuilder() => $UserBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is $User &&
        id == other.id &&
        username == other.username &&
        displayName == other.displayName &&
        roles == other.roles &&
        uploadEnabled == other.uploadEnabled &&
        managePodcasts == other.managePodcasts &&
        delete == other.delete;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, username.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, roles.hashCode);
    _$hash = $jc(_$hash, uploadEnabled.hashCode);
    _$hash = $jc(_$hash, managePodcasts.hashCode);
    _$hash = $jc(_$hash, delete.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'$User')
          ..add('id', id)
          ..add('username', username)
          ..add('displayName', displayName)
          ..add('roles', roles)
          ..add('uploadEnabled', uploadEnabled)
          ..add('managePodcasts', managePodcasts)
          ..add('delete', delete))
        .toString();
  }
}

class $UserBuilder implements Builder<$User, $UserBuilder>, UserBuilder {
  _$$User? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(covariant String? id) => _$this._id = id;

  String? _username;
  String? get username => _$this._username;
  set username(covariant String? username) => _$this._username = username;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(covariant String? displayName) =>
      _$this._displayName = displayName;

  ListBuilder<String>? _roles;
  ListBuilder<String> get roles => _$this._roles ??= ListBuilder<String>();
  set roles(covariant ListBuilder<String>? roles) => _$this._roles = roles;

  bool? _uploadEnabled;
  bool? get uploadEnabled => _$this._uploadEnabled;
  set uploadEnabled(covariant bool? uploadEnabled) =>
      _$this._uploadEnabled = uploadEnabled;

  bool? _managePodcasts;
  bool? get managePodcasts => _$this._managePodcasts;
  set managePodcasts(covariant bool? managePodcasts) =>
      _$this._managePodcasts = managePodcasts;

  bool? _delete;
  bool? get delete => _$this._delete;
  set delete(covariant bool? delete) => _$this._delete = delete;

  $UserBuilder() {
    $User._defaults(this);
  }

  $UserBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _username = $v.username;
      _displayName = $v.displayName;
      _roles = $v.roles.toBuilder();
      _uploadEnabled = $v.uploadEnabled;
      _managePodcasts = $v.managePodcasts;
      _delete = $v.delete;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant $User other) {
    _$v = other as _$$User;
  }

  @override
  void update(void Function($UserBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  $User build() => _build();

  _$$User _build() {
    _$$User _$result;
    try {
      _$result =
          _$v ??
          _$$User._(
            id: BuiltValueNullFieldError.checkNotNull(id, r'$User', 'id'),
            username: BuiltValueNullFieldError.checkNotNull(
              username,
              r'$User',
              'username',
            ),
            displayName: displayName,
            roles: roles.build(),
            uploadEnabled: BuiltValueNullFieldError.checkNotNull(
              uploadEnabled,
              r'$User',
              'uploadEnabled',
            ),
            managePodcasts: managePodcasts,
            delete: delete,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'roles';
        roles.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'$User', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
