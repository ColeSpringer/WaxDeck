// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_card_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EntityCardList extends EntityCardList {
  @override
  final BuiltList<EntityCard> entities;

  factory _$EntityCardList([void Function(EntityCardListBuilder)? updates]) =>
      (EntityCardListBuilder()..update(updates))._build();

  _$EntityCardList._({required this.entities}) : super._();
  @override
  EntityCardList rebuild(void Function(EntityCardListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EntityCardListBuilder toBuilder() => EntityCardListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EntityCardList && entities == other.entities;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entities.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'EntityCardList',
    )..add('entities', entities)).toString();
  }
}

class EntityCardListBuilder
    implements Builder<EntityCardList, EntityCardListBuilder> {
  _$EntityCardList? _$v;

  ListBuilder<EntityCard>? _entities;
  ListBuilder<EntityCard> get entities =>
      _$this._entities ??= ListBuilder<EntityCard>();
  set entities(ListBuilder<EntityCard>? entities) =>
      _$this._entities = entities;

  EntityCardListBuilder() {
    EntityCardList._defaults(this);
  }

  EntityCardListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entities = $v.entities.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EntityCardList other) {
    _$v = other as _$EntityCardList;
  }

  @override
  void update(void Function(EntityCardListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EntityCardList build() => _build();

  _$EntityCardList _build() {
    _$EntityCardList _$result;
    try {
      _$result = _$v ?? _$EntityCardList._(entities: entities.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entities';
        entities.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EntityCardList',
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
