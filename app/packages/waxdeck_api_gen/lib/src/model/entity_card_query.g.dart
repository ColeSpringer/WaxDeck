// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_card_query.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EntityCardQuery extends EntityCardQuery {
  @override
  final BuiltList<String> pids;

  factory _$EntityCardQuery([void Function(EntityCardQueryBuilder)? updates]) =>
      (EntityCardQueryBuilder()..update(updates))._build();

  _$EntityCardQuery._({required this.pids}) : super._();
  @override
  EntityCardQuery rebuild(void Function(EntityCardQueryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EntityCardQueryBuilder toBuilder() => EntityCardQueryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EntityCardQuery && pids == other.pids;
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
      r'EntityCardQuery',
    )..add('pids', pids)).toString();
  }
}

class EntityCardQueryBuilder
    implements Builder<EntityCardQuery, EntityCardQueryBuilder> {
  _$EntityCardQuery? _$v;

  ListBuilder<String>? _pids;
  ListBuilder<String> get pids => _$this._pids ??= ListBuilder<String>();
  set pids(ListBuilder<String>? pids) => _$this._pids = pids;

  EntityCardQueryBuilder() {
    EntityCardQuery._defaults(this);
  }

  EntityCardQueryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pids = $v.pids.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EntityCardQuery other) {
    _$v = other as _$EntityCardQuery;
  }

  @override
  void update(void Function(EntityCardQueryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EntityCardQuery build() => _build();

  _$EntityCardQuery _build() {
    _$EntityCardQuery _$result;
    try {
      _$result = _$v ?? _$EntityCardQuery._(pids: pids.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'pids';
        pids.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EntityCardQuery',
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
