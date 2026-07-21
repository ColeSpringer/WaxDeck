// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_plan.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OrganizePlan extends OrganizePlan {
  @override
  final String profile;
  @override
  final int totalActions;
  @override
  final BuiltList<OrganizeAction> actions;
  @override
  final bool? tagWrite;

  factory _$OrganizePlan([void Function(OrganizePlanBuilder)? updates]) =>
      (OrganizePlanBuilder()..update(updates))._build();

  _$OrganizePlan._({
    required this.profile,
    required this.totalActions,
    required this.actions,
    this.tagWrite,
  }) : super._();
  @override
  OrganizePlan rebuild(void Function(OrganizePlanBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OrganizePlanBuilder toBuilder() => OrganizePlanBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizePlan &&
        profile == other.profile &&
        totalActions == other.totalActions &&
        actions == other.actions &&
        tagWrite == other.tagWrite;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, profile.hashCode);
    _$hash = $jc(_$hash, totalActions.hashCode);
    _$hash = $jc(_$hash, actions.hashCode);
    _$hash = $jc(_$hash, tagWrite.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizePlan')
          ..add('profile', profile)
          ..add('totalActions', totalActions)
          ..add('actions', actions)
          ..add('tagWrite', tagWrite))
        .toString();
  }
}

class OrganizePlanBuilder
    implements Builder<OrganizePlan, OrganizePlanBuilder> {
  _$OrganizePlan? _$v;

  String? _profile;
  String? get profile => _$this._profile;
  set profile(String? profile) => _$this._profile = profile;

  int? _totalActions;
  int? get totalActions => _$this._totalActions;
  set totalActions(int? totalActions) => _$this._totalActions = totalActions;

  ListBuilder<OrganizeAction>? _actions;
  ListBuilder<OrganizeAction> get actions =>
      _$this._actions ??= ListBuilder<OrganizeAction>();
  set actions(ListBuilder<OrganizeAction>? actions) =>
      _$this._actions = actions;

  bool? _tagWrite;
  bool? get tagWrite => _$this._tagWrite;
  set tagWrite(bool? tagWrite) => _$this._tagWrite = tagWrite;

  OrganizePlanBuilder() {
    OrganizePlan._defaults(this);
  }

  OrganizePlanBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _profile = $v.profile;
      _totalActions = $v.totalActions;
      _actions = $v.actions.toBuilder();
      _tagWrite = $v.tagWrite;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizePlan other) {
    _$v = other as _$OrganizePlan;
  }

  @override
  void update(void Function(OrganizePlanBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizePlan build() => _build();

  _$OrganizePlan _build() {
    _$OrganizePlan _$result;
    try {
      _$result =
          _$v ??
          _$OrganizePlan._(
            profile: BuiltValueNullFieldError.checkNotNull(
              profile,
              r'OrganizePlan',
              'profile',
            ),
            totalActions: BuiltValueNullFieldError.checkNotNull(
              totalActions,
              r'OrganizePlan',
              'totalActions',
            ),
            actions: actions.build(),
            tagWrite: tagWrite,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'actions';
        actions.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'OrganizePlan',
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
