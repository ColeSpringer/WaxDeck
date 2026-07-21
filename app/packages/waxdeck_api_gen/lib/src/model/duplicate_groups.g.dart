// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'duplicate_groups.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DuplicateGroups extends DuplicateGroups {
  @override
  final BuiltList<DuplicateGroup> groups;

  factory _$DuplicateGroups([void Function(DuplicateGroupsBuilder)? updates]) =>
      (DuplicateGroupsBuilder()..update(updates))._build();

  _$DuplicateGroups._({required this.groups}) : super._();
  @override
  DuplicateGroups rebuild(void Function(DuplicateGroupsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DuplicateGroupsBuilder toBuilder() => DuplicateGroupsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DuplicateGroups && groups == other.groups;
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
      r'DuplicateGroups',
    )..add('groups', groups)).toString();
  }
}

class DuplicateGroupsBuilder
    implements Builder<DuplicateGroups, DuplicateGroupsBuilder> {
  _$DuplicateGroups? _$v;

  ListBuilder<DuplicateGroup>? _groups;
  ListBuilder<DuplicateGroup> get groups =>
      _$this._groups ??= ListBuilder<DuplicateGroup>();
  set groups(ListBuilder<DuplicateGroup>? groups) => _$this._groups = groups;

  DuplicateGroupsBuilder() {
    DuplicateGroups._defaults(this);
  }

  DuplicateGroupsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _groups = $v.groups.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DuplicateGroups other) {
    _$v = other as _$DuplicateGroups;
  }

  @override
  void update(void Function(DuplicateGroupsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DuplicateGroups build() => _build();

  _$DuplicateGroups _build() {
    _$DuplicateGroups _$result;
    try {
      _$result = _$v ?? _$DuplicateGroups._(groups: groups.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'groups';
        groups.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'DuplicateGroups',
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
