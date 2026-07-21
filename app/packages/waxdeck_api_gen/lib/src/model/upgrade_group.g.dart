// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upgrade_group.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpgradeGroup extends UpgradeGroup {
  @override
  final BuiltList<UpgradeMember> members;

  factory _$UpgradeGroup([void Function(UpgradeGroupBuilder)? updates]) =>
      (UpgradeGroupBuilder()..update(updates))._build();

  _$UpgradeGroup._({required this.members}) : super._();
  @override
  UpgradeGroup rebuild(void Function(UpgradeGroupBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpgradeGroupBuilder toBuilder() => UpgradeGroupBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpgradeGroup && members == other.members;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, members.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'UpgradeGroup',
    )..add('members', members)).toString();
  }
}

class UpgradeGroupBuilder
    implements Builder<UpgradeGroup, UpgradeGroupBuilder> {
  _$UpgradeGroup? _$v;

  ListBuilder<UpgradeMember>? _members;
  ListBuilder<UpgradeMember> get members =>
      _$this._members ??= ListBuilder<UpgradeMember>();
  set members(ListBuilder<UpgradeMember>? members) => _$this._members = members;

  UpgradeGroupBuilder() {
    UpgradeGroup._defaults(this);
  }

  UpgradeGroupBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _members = $v.members.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpgradeGroup other) {
    _$v = other as _$UpgradeGroup;
  }

  @override
  void update(void Function(UpgradeGroupBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpgradeGroup build() => _build();

  _$UpgradeGroup _build() {
    _$UpgradeGroup _$result;
    try {
      _$result = _$v ?? _$UpgradeGroup._(members: members.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'members';
        members.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'UpgradeGroup',
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
