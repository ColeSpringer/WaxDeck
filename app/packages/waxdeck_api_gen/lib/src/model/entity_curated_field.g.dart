// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_curated_field.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EntityCuratedField extends EntityCuratedField {
  @override
  final String field;
  @override
  final String? value;
  @override
  final String source_;
  @override
  final bool locked;
  @override
  final DateTime? updatedAt;

  factory _$EntityCuratedField([
    void Function(EntityCuratedFieldBuilder)? updates,
  ]) => (EntityCuratedFieldBuilder()..update(updates))._build();

  _$EntityCuratedField._({
    required this.field,
    this.value,
    required this.source_,
    required this.locked,
    this.updatedAt,
  }) : super._();
  @override
  EntityCuratedField rebuild(
    void Function(EntityCuratedFieldBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EntityCuratedFieldBuilder toBuilder() =>
      EntityCuratedFieldBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EntityCuratedField &&
        field == other.field &&
        value == other.value &&
        source_ == other.source_ &&
        locked == other.locked &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, field.hashCode);
    _$hash = $jc(_$hash, value.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, locked.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EntityCuratedField')
          ..add('field', field)
          ..add('value', value)
          ..add('source_', source_)
          ..add('locked', locked)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class EntityCuratedFieldBuilder
    implements Builder<EntityCuratedField, EntityCuratedFieldBuilder> {
  _$EntityCuratedField? _$v;

  String? _field;
  String? get field => _$this._field;
  set field(String? field) => _$this._field = field;

  String? _value;
  String? get value => _$this._value;
  set value(String? value) => _$this._value = value;

  String? _source_;
  String? get source_ => _$this._source_;
  set source_(String? source_) => _$this._source_ = source_;

  bool? _locked;
  bool? get locked => _$this._locked;
  set locked(bool? locked) => _$this._locked = locked;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  EntityCuratedFieldBuilder() {
    EntityCuratedField._defaults(this);
  }

  EntityCuratedFieldBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _field = $v.field;
      _value = $v.value;
      _source_ = $v.source_;
      _locked = $v.locked;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EntityCuratedField other) {
    _$v = other as _$EntityCuratedField;
  }

  @override
  void update(void Function(EntityCuratedFieldBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EntityCuratedField build() => _build();

  _$EntityCuratedField _build() {
    final _$result =
        _$v ??
        _$EntityCuratedField._(
          field: BuiltValueNullFieldError.checkNotNull(
            field,
            r'EntityCuratedField',
            'field',
          ),
          value: value,
          source_: BuiltValueNullFieldError.checkNotNull(
            source_,
            r'EntityCuratedField',
            'source_',
          ),
          locked: BuiltValueNullFieldError.checkNotNull(
            locked,
            r'EntityCuratedField',
            'locked',
          ),
          updatedAt: updatedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
