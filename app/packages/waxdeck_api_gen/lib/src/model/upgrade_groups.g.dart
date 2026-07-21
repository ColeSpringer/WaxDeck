// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upgrade_groups.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpgradeGroups extends UpgradeGroups {
  @override
  final BuiltList<UpgradeGroup> groups;

  factory _$UpgradeGroups([void Function(UpgradeGroupsBuilder)? updates]) =>
      (UpgradeGroupsBuilder()..update(updates))._build();

  _$UpgradeGroups._({required this.groups}) : super._();
  @override
  UpgradeGroups rebuild(void Function(UpgradeGroupsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpgradeGroupsBuilder toBuilder() => UpgradeGroupsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpgradeGroups && groups == other.groups;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, groups.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'UpgradeGroups',
    )..add('groups', groups)).toString();
  }
}

class UpgradeGroupsBuilder
    implements Builder<UpgradeGroups, UpgradeGroupsBuilder> {
  _$UpgradeGroups? _$v;

  ListBuilder<UpgradeGroup>? _groups;
  ListBuilder<UpgradeGroup> get groups =>
      _$this._groups ??= ListBuilder<UpgradeGroup>();
  set groups(ListBuilder<UpgradeGroup>? groups) => _$this._groups = groups;

  UpgradeGroupsBuilder() {
    UpgradeGroups._defaults(this);
  }

  UpgradeGroupsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _groups = $v.groups.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpgradeGroups other) {
    _$v = other as _$UpgradeGroups;
  }

  @override
  void update(void Function(UpgradeGroupsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpgradeGroups build() => _build();

  _$UpgradeGroups _build() {
    _$UpgradeGroups _$result;
    try {
      _$result = _$v ?? _$UpgradeGroups._(groups: groups.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'groups';
        groups.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'UpgradeGroups',
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
