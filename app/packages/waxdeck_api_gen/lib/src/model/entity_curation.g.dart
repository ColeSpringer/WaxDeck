// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_curation.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EntityCuration extends EntityCuration {
  @override
  final BuiltList<EntityCuratedField> curated;

  factory _$EntityCuration([void Function(EntityCurationBuilder)? updates]) =>
      (EntityCurationBuilder()..update(updates))._build();

  _$EntityCuration._({required this.curated}) : super._();
  @override
  EntityCuration rebuild(void Function(EntityCurationBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EntityCurationBuilder toBuilder() => EntityCurationBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EntityCuration && curated == other.curated;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, curated.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'EntityCuration',
    )..add('curated', curated)).toString();
  }
}

class EntityCurationBuilder
    implements Builder<EntityCuration, EntityCurationBuilder> {
  _$EntityCuration? _$v;

  ListBuilder<EntityCuratedField>? _curated;
  ListBuilder<EntityCuratedField> get curated =>
      _$this._curated ??= ListBuilder<EntityCuratedField>();
  set curated(ListBuilder<EntityCuratedField>? curated) =>
      _$this._curated = curated;

  EntityCurationBuilder() {
    EntityCuration._defaults(this);
  }

  EntityCurationBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _curated = $v.curated.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EntityCuration other) {
    _$v = other as _$EntityCuration;
  }

  @override
  void update(void Function(EntityCurationBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EntityCuration build() => _build();

  _$EntityCuration _build() {
    _$EntityCuration _$result;
    try {
      _$result = _$v ?? _$EntityCuration._(curated: curated.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'curated';
        curated.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EntityCuration',
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
