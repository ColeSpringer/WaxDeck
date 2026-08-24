// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item_permissions.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ItemPermissions extends ItemPermissions {
  @override
  final bool mayCurate;

  factory _$ItemPermissions([void Function(ItemPermissionsBuilder)? updates]) =>
      (ItemPermissionsBuilder()..update(updates))._build();

  _$ItemPermissions._({required this.mayCurate}) : super._();
  @override
  ItemPermissions rebuild(void Function(ItemPermissionsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ItemPermissionsBuilder toBuilder() => ItemPermissionsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ItemPermissions && mayCurate == other.mayCurate;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, mayCurate.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'ItemPermissions',
    )..add('mayCurate', mayCurate)).toString();
  }
}

class ItemPermissionsBuilder
    implements Builder<ItemPermissions, ItemPermissionsBuilder> {
  _$ItemPermissions? _$v;

  bool? _mayCurate;
  bool? get mayCurate => _$this._mayCurate;
  set mayCurate(bool? mayCurate) => _$this._mayCurate = mayCurate;

  ItemPermissionsBuilder() {
    ItemPermissions._defaults(this);
  }

  ItemPermissionsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _mayCurate = $v.mayCurate;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ItemPermissions other) {
    _$v = other as _$ItemPermissions;
  }

  @override
  void update(void Function(ItemPermissionsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ItemPermissions build() => _build();

  _$ItemPermissions _build() {
    final _$result =
        _$v ??
        _$ItemPermissions._(
          mayCurate: BuiltValueNullFieldError.checkNotNull(
            mayCurate,
            r'ItemPermissions',
            'mayCurate',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
