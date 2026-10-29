// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'removed_item_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RemovedItemList extends RemovedItemList {
  @override
  final BuiltList<String> pids;

  factory _$RemovedItemList([void Function(RemovedItemListBuilder)? updates]) =>
      (RemovedItemListBuilder()..update(updates))._build();

  _$RemovedItemList._({required this.pids}) : super._();
  @override
  RemovedItemList rebuild(void Function(RemovedItemListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RemovedItemListBuilder toBuilder() => RemovedItemListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RemovedItemList && pids == other.pids;
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
      r'RemovedItemList',
    )..add('pids', pids)).toString();
  }
}

class RemovedItemListBuilder
    implements Builder<RemovedItemList, RemovedItemListBuilder> {
  _$RemovedItemList? _$v;

  ListBuilder<String>? _pids;
  ListBuilder<String> get pids => _$this._pids ??= ListBuilder<String>();
  set pids(ListBuilder<String>? pids) => _$this._pids = pids;

  RemovedItemListBuilder() {
    RemovedItemList._defaults(this);
  }

  RemovedItemListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pids = $v.pids.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RemovedItemList other) {
    _$v = other as _$RemovedItemList;
  }

  @override
  void update(void Function(RemovedItemListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RemovedItemList build() => _build();

  _$RemovedItemList _build() {
    _$RemovedItemList _$result;
    try {
      _$result = _$v ?? _$RemovedItemList._(pids: pids.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'pids';
        pids.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'RemovedItemList',
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
