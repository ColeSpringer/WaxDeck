// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rule_field.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RuleField extends RuleField {
  @override
  final String name;
  @override
  final String kind;
  @override
  final BuiltList<String> ops;
  @override
  final bool userState;
  @override
  final bool sortable;
  @override
  final String? description;

  factory _$RuleField([void Function(RuleFieldBuilder)? updates]) =>
      (RuleFieldBuilder()..update(updates))._build();

  _$RuleField._({
    required this.name,
    required this.kind,
    required this.ops,
    required this.userState,
    required this.sortable,
    this.description,
  }) : super._();
  @override
  RuleField rebuild(void Function(RuleFieldBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RuleFieldBuilder toBuilder() => RuleFieldBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RuleField &&
        name == other.name &&
        kind == other.kind &&
        ops == other.ops &&
        userState == other.userState &&
        sortable == other.sortable &&
        description == other.description;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, ops.hashCode);
    _$hash = $jc(_$hash, userState.hashCode);
    _$hash = $jc(_$hash, sortable.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RuleField')
          ..add('name', name)
          ..add('kind', kind)
          ..add('ops', ops)
          ..add('userState', userState)
          ..add('sortable', sortable)
          ..add('description', description))
        .toString();
  }
}

class RuleFieldBuilder implements Builder<RuleField, RuleFieldBuilder> {
  _$RuleField? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  ListBuilder<String>? _ops;
  ListBuilder<String> get ops => _$this._ops ??= ListBuilder<String>();
  set ops(ListBuilder<String>? ops) => _$this._ops = ops;

  bool? _userState;
  bool? get userState => _$this._userState;
  set userState(bool? userState) => _$this._userState = userState;

  bool? _sortable;
  bool? get sortable => _$this._sortable;
  set sortable(bool? sortable) => _$this._sortable = sortable;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  RuleFieldBuilder() {
    RuleField._defaults(this);
  }

  RuleFieldBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _kind = $v.kind;
      _ops = $v.ops.toBuilder();
      _userState = $v.userState;
      _sortable = $v.sortable;
      _description = $v.description;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RuleField other) {
    _$v = other as _$RuleField;
  }

  @override
  void update(void Function(RuleFieldBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RuleField build() => _build();

  _$RuleField _build() {
    _$RuleField _$result;
    try {
      _$result =
          _$v ??
          _$RuleField._(
            name: BuiltValueNullFieldError.checkNotNull(
              name,
              r'RuleField',
              'name',
            ),
            kind: BuiltValueNullFieldError.checkNotNull(
              kind,
              r'RuleField',
              'kind',
            ),
            ops: ops.build(),
            userState: BuiltValueNullFieldError.checkNotNull(
              userState,
              r'RuleField',
              'userState',
            ),
            sortable: BuiltValueNullFieldError.checkNotNull(
              sortable,
              r'RuleField',
              'sortable',
            ),
            description: description,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'ops';
        ops.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'RuleField',
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
