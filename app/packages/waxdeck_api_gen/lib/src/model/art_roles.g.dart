// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'art_roles.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ArtRoles extends ArtRoles {
  @override
  final BuiltList<ArtRoleInfo> roles;
  @override
  final ArtSource? artSource;

  factory _$ArtRoles([void Function(ArtRolesBuilder)? updates]) =>
      (ArtRolesBuilder()..update(updates))._build();

  _$ArtRoles._({required this.roles, this.artSource}) : super._();
  @override
  ArtRoles rebuild(void Function(ArtRolesBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ArtRolesBuilder toBuilder() => ArtRolesBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ArtRoles &&
        roles == other.roles &&
        artSource == other.artSource;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, roles.hashCode);
    _$hash = $jc(_$hash, artSource.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ArtRoles')
          ..add('roles', roles)
          ..add('artSource', artSource))
        .toString();
  }
}

class ArtRolesBuilder implements Builder<ArtRoles, ArtRolesBuilder> {
  _$ArtRoles? _$v;

  ListBuilder<ArtRoleInfo>? _roles;
  ListBuilder<ArtRoleInfo> get roles =>
      _$this._roles ??= ListBuilder<ArtRoleInfo>();
  set roles(ListBuilder<ArtRoleInfo>? roles) => _$this._roles = roles;

  ArtSourceBuilder? _artSource;
  ArtSourceBuilder get artSource => _$this._artSource ??= ArtSourceBuilder();
  set artSource(ArtSourceBuilder? artSource) => _$this._artSource = artSource;

  ArtRolesBuilder() {
    ArtRoles._defaults(this);
  }

  ArtRolesBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _roles = $v.roles.toBuilder();
      _artSource = $v.artSource?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ArtRoles other) {
    _$v = other as _$ArtRoles;
  }

  @override
  void update(void Function(ArtRolesBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ArtRoles build() => _build();

  _$ArtRoles _build() {
    _$ArtRoles _$result;
    try {
      _$result =
          _$v ??
          _$ArtRoles._(roles: roles.build(), artSource: _artSource?.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'roles';
        roles.build();
        _$failedField = 'artSource';
        _artSource?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ArtRoles',
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
