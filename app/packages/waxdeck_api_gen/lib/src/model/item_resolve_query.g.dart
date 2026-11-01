// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item_resolve_query.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ItemResolveQuery extends ItemResolveQuery {
  @override
  final BuiltList<String> pids;

  factory _$ItemResolveQuery([
    void Function(ItemResolveQueryBuilder)? updates,
  ]) => (ItemResolveQueryBuilder()..update(updates))._build();

  _$ItemResolveQuery._({required this.pids}) : super._();
  @override
  ItemResolveQuery rebuild(void Function(ItemResolveQueryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ItemResolveQueryBuilder toBuilder() =>
      ItemResolveQueryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ItemResolveQuery && pids == other.pids;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pids.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'ItemResolveQuery',
    )..add('pids', pids)).toString();
  }
}

class ItemResolveQueryBuilder
    implements Builder<ItemResolveQuery, ItemResolveQueryBuilder> {
  _$ItemResolveQuery? _$v;

  ListBuilder<String>? _pids;
  ListBuilder<String> get pids => _$this._pids ??= ListBuilder<String>();
  set pids(ListBuilder<String>? pids) => _$this._pids = pids;

  ItemResolveQueryBuilder() {
    ItemResolveQuery._defaults(this);
  }

  ItemResolveQueryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pids = $v.pids.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ItemResolveQuery other) {
    _$v = other as _$ItemResolveQuery;
  }

  @override
  void update(void Function(ItemResolveQueryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ItemResolveQuery build() => _build();

  _$ItemResolveQuery _build() {
    _$ItemResolveQuery _$result;
    try {
      _$result = _$v ?? _$ItemResolveQuery._(pids: pids.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'pids';
        pids.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ItemResolveQuery',
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
