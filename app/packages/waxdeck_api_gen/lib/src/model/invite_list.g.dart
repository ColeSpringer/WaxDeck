// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InviteList extends InviteList {
  @override
  final BuiltList<Invite> invites;

  factory _$InviteList([void Function(InviteListBuilder)? updates]) =>
      (InviteListBuilder()..update(updates))._build();

  _$InviteList._({required this.invites}) : super._();
  @override
  InviteList rebuild(void Function(InviteListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InviteListBuilder toBuilder() => InviteListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InviteList && invites == other.invites;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, invites.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'InviteList',
    )..add('invites', invites)).toString();
  }
}

class InviteListBuilder implements Builder<InviteList, InviteListBuilder> {
  _$InviteList? _$v;

  ListBuilder<Invite>? _invites;
  ListBuilder<Invite> get invites => _$this._invites ??= ListBuilder<Invite>();
  set invites(ListBuilder<Invite>? invites) => _$this._invites = invites;

  InviteListBuilder() {
    InviteList._defaults(this);
  }

  InviteListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _invites = $v.invites.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InviteList other) {
    _$v = other as _$InviteList;
  }

  @override
  void update(void Function(InviteListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InviteList build() => _build();

  _$InviteList _build() {
    _$InviteList _$result;
    try {
      _$result = _$v ?? _$InviteList._(invites: invites.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'invites';
        invites.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'InviteList',
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
