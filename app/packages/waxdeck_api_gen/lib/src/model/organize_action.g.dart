// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_action.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OrganizeAction extends OrganizeAction {
  @override
  final String itemPid;
  @override
  final String from;
  @override
  final String to;

  factory _$OrganizeAction([void Function(OrganizeActionBuilder)? updates]) =>
      (OrganizeActionBuilder()..update(updates))._build();

  _$OrganizeAction._({
    required this.itemPid,
    required this.from,
    required this.to,
  }) : super._();
  @override
  OrganizeAction rebuild(void Function(OrganizeActionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OrganizeActionBuilder toBuilder() => OrganizeActionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizeAction &&
        itemPid == other.itemPid &&
        from == other.from &&
        to == other.to;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, itemPid.hashCode);
    _$hash = $jc(_$hash, from.hashCode);
    _$hash = $jc(_$hash, to.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizeAction')
          ..add('itemPid', itemPid)
          ..add('from', from)
          ..add('to', to))
        .toString();
  }
}

class OrganizeActionBuilder
    implements Builder<OrganizeAction, OrganizeActionBuilder> {
  _$OrganizeAction? _$v;

  String? _itemPid;
  String? get itemPid => _$this._itemPid;
  set itemPid(String? itemPid) => _$this._itemPid = itemPid;

  String? _from;
  String? get from => _$this._from;
  set from(String? from) => _$this._from = from;

  String? _to;
  String? get to => _$this._to;
  set to(String? to) => _$this._to = to;

  OrganizeActionBuilder() {
    OrganizeAction._defaults(this);
  }

  OrganizeActionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _itemPid = $v.itemPid;
      _from = $v.from;
      _to = $v.to;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizeAction other) {
    _$v = other as _$OrganizeAction;
  }

  @override
  void update(void Function(OrganizeActionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizeAction build() => _build();

  _$OrganizeAction _build() {
    final _$result =
        _$v ??
        _$OrganizeAction._(
          itemPid: BuiltValueNullFieldError.checkNotNull(
            itemPid,
            r'OrganizeAction',
            'itemPid',
          ),
          from: BuiltValueNullFieldError.checkNotNull(
            from,
            r'OrganizeAction',
            'from',
          ),
          to: BuiltValueNullFieldError.checkNotNull(
            to,
            r'OrganizeAction',
            'to',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
