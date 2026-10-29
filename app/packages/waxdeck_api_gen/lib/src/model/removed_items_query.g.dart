// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'removed_items_query.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RemovedItemsQuery extends RemovedItemsQuery {
  @override
  final BuiltList<String> pids;

  factory _$RemovedItemsQuery([
    void Function(RemovedItemsQueryBuilder)? updates,
  ]) => (RemovedItemsQueryBuilder()..update(updates))._build();

  _$RemovedItemsQuery._({required this.pids}) : super._();
  @override
  RemovedItemsQuery rebuild(void Function(RemovedItemsQueryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RemovedItemsQueryBuilder toBuilder() =>
      RemovedItemsQueryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RemovedItemsQuery && pids == other.pids;
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
      r'RemovedItemsQuery',
    )..add('pids', pids)).toString();
  }
}

class RemovedItemsQueryBuilder
    implements Builder<RemovedItemsQuery, RemovedItemsQueryBuilder> {
  _$RemovedItemsQuery? _$v;

  ListBuilder<String>? _pids;
  ListBuilder<String> get pids => _$this._pids ??= ListBuilder<String>();
  set pids(ListBuilder<String>? pids) => _$this._pids = pids;

  RemovedItemsQueryBuilder() {
    RemovedItemsQuery._defaults(this);
  }

  RemovedItemsQueryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pids = $v.pids.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RemovedItemsQuery other) {
    _$v = other as _$RemovedItemsQuery;
  }

  @override
  void update(void Function(RemovedItemsQueryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RemovedItemsQuery build() => _build();

  _$RemovedItemsQuery _build() {
    _$RemovedItemsQuery _$result;
    try {
      _$result = _$v ?? _$RemovedItemsQuery._(pids: pids.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'pids';
        pids.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'RemovedItemsQuery',
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
