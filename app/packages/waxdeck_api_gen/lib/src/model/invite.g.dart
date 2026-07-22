// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

abstract mixin class InviteBuilder {
  void replace(Invite other);
  void update(void Function(InviteBuilder) updates);
  String? get id;
  set id(String? id);

  String? get note;
  set note(String? note);

  ListBuilder<Role> get roles;
  set roles(ListBuilder<Role>? roles);

  LibraryAccessBuilder get libraryAccess;
  set libraryAccess(LibraryAccessBuilder? libraryAccess);

  PermissionsBuilder get permissions;
  set permissions(PermissionsBuilder? permissions);

  bool? get uploadEnabled;
  set uploadEnabled(bool? uploadEnabled);

  int? get maxUses;
  set maxUses(int? maxUses);

  int? get usedCount;
  set usedCount(int? usedCount);

  bool? get revoked;
  set revoked(bool? revoked);

  DateTime? get expiresAt;
  set expiresAt(DateTime? expiresAt);

  DateTime? get createdAt;
  set createdAt(DateTime? createdAt);

  String? get createdBy;
  set createdBy(String? createdBy);
}

class _$$Invite extends $Invite {
  @override
  final String id;
  @override
  final String? note;
  @override
  final BuiltList<Role> roles;
  @override
  final LibraryAccess? libraryAccess;
  @override
  final Permissions? permissions;
  @override
  final bool uploadEnabled;
  @override
  final int maxUses;
  @override
  final int usedCount;
  @override
  final bool revoked;
  @override
  final DateTime? expiresAt;
  @override
  final DateTime createdAt;
  @override
  final String? createdBy;

  factory _$$Invite([void Function($InviteBuilder)? updates]) =>
      ($InviteBuilder()..update(updates))._build();

  _$$Invite._({
    required this.id,
    this.note,
    required this.roles,
    this.libraryAccess,
    this.permissions,
    required this.uploadEnabled,
    required this.maxUses,
    required this.usedCount,
    required this.revoked,
    this.expiresAt,
    required this.createdAt,
    this.createdBy,
  }) : super._();
  @override
  $Invite rebuild(void Function($InviteBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  $InviteBuilder toBuilder() => $InviteBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is $Invite &&
        id == other.id &&
        note == other.note &&
        roles == other.roles &&
        libraryAccess == other.libraryAccess &&
        permissions == other.permissions &&
        uploadEnabled == other.uploadEnabled &&
        maxUses == other.maxUses &&
        usedCount == other.usedCount &&
        revoked == other.revoked &&
        expiresAt == other.expiresAt &&
        createdAt == other.createdAt &&
        createdBy == other.createdBy;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, roles.hashCode);
    _$hash = $jc(_$hash, libraryAccess.hashCode);
    _$hash = $jc(_$hash, permissions.hashCode);
    _$hash = $jc(_$hash, uploadEnabled.hashCode);
    _$hash = $jc(_$hash, maxUses.hashCode);
    _$hash = $jc(_$hash, usedCount.hashCode);
    _$hash = $jc(_$hash, revoked.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, createdBy.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'$Invite')
          ..add('id', id)
          ..add('note', note)
          ..add('roles', roles)
          ..add('libraryAccess', libraryAccess)
          ..add('permissions', permissions)
          ..add('uploadEnabled', uploadEnabled)
          ..add('maxUses', maxUses)
          ..add('usedCount', usedCount)
          ..add('revoked', revoked)
          ..add('expiresAt', expiresAt)
          ..add('createdAt', createdAt)
          ..add('createdBy', createdBy))
        .toString();
  }
}

class $InviteBuilder
    implements Builder<$Invite, $InviteBuilder>, InviteBuilder {
  _$$Invite? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(covariant String? id) => _$this._id = id;

  String? _note;
  String? get note => _$this._note;
  set note(covariant String? note) => _$this._note = note;

  ListBuilder<Role>? _roles;
  ListBuilder<Role> get roles => _$this._roles ??= ListBuilder<Role>();
  set roles(covariant ListBuilder<Role>? roles) => _$this._roles = roles;

  LibraryAccessBuilder? _libraryAccess;
  LibraryAccessBuilder get libraryAccess =>
      _$this._libraryAccess ??= LibraryAccessBuilder();
  set libraryAccess(covariant LibraryAccessBuilder? libraryAccess) =>
      _$this._libraryAccess = libraryAccess;

  PermissionsBuilder? _permissions;
  PermissionsBuilder get permissions =>
      _$this._permissions ??= PermissionsBuilder();
  set permissions(covariant PermissionsBuilder? permissions) =>
      _$this._permissions = permissions;

  bool? _uploadEnabled;
  bool? get uploadEnabled => _$this._uploadEnabled;
  set uploadEnabled(covariant bool? uploadEnabled) =>
      _$this._uploadEnabled = uploadEnabled;

  int? _maxUses;
  int? get maxUses => _$this._maxUses;
  set maxUses(covariant int? maxUses) => _$this._maxUses = maxUses;

  int? _usedCount;
  int? get usedCount => _$this._usedCount;
  set usedCount(covariant int? usedCount) => _$this._usedCount = usedCount;

  bool? _revoked;
  bool? get revoked => _$this._revoked;
  set revoked(covariant bool? revoked) => _$this._revoked = revoked;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(covariant DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(covariant DateTime? createdAt) => _$this._createdAt = createdAt;

  String? _createdBy;
  String? get createdBy => _$this._createdBy;
  set createdBy(covariant String? createdBy) => _$this._createdBy = createdBy;

  $InviteBuilder() {
    $Invite._defaults(this);
  }

  $InviteBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _note = $v.note;
      _roles = $v.roles.toBuilder();
      _libraryAccess = $v.libraryAccess?.toBuilder();
      _permissions = $v.permissions?.toBuilder();
      _uploadEnabled = $v.uploadEnabled;
      _maxUses = $v.maxUses;
      _usedCount = $v.usedCount;
      _revoked = $v.revoked;
      _expiresAt = $v.expiresAt;
      _createdAt = $v.createdAt;
      _createdBy = $v.createdBy;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant $Invite other) {
    _$v = other as _$$Invite;
  }

  @override
  void update(void Function($InviteBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  $Invite build() => _build();

  _$$Invite _build() {
    _$$Invite _$result;
    try {
      _$result =
          _$v ??
          _$$Invite._(
            id: BuiltValueNullFieldError.checkNotNull(id, r'$Invite', 'id'),
            note: note,
            roles: roles.build(),
            libraryAccess: _libraryAccess?.build(),
            permissions: _permissions?.build(),
            uploadEnabled: BuiltValueNullFieldError.checkNotNull(
              uploadEnabled,
              r'$Invite',
              'uploadEnabled',
            ),
            maxUses: BuiltValueNullFieldError.checkNotNull(
              maxUses,
              r'$Invite',
              'maxUses',
            ),
            usedCount: BuiltValueNullFieldError.checkNotNull(
              usedCount,
              r'$Invite',
              'usedCount',
            ),
            revoked: BuiltValueNullFieldError.checkNotNull(
              revoked,
              r'$Invite',
              'revoked',
            ),
            expiresAt: expiresAt,
            createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt,
              r'$Invite',
              'createdAt',
            ),
            createdBy: createdBy,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'roles';
        roles.build();
        _$failedField = 'libraryAccess';
        _libraryAccess?.build();
        _$failedField = 'permissions';
        _permissions?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'$Invite',
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
