// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_edit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EntityEdit extends EntityEdit {
  @override
  final BuiltMap<String, String> edits;
  @override
  final bool? writeBack;
  @override
  final bool? lock;
  @override
  final bool? force;

  factory _$EntityEdit([void Function(EntityEditBuilder)? updates]) =>
      (EntityEditBuilder()..update(updates))._build();

  _$EntityEdit._({required this.edits, this.writeBack, this.lock, this.force})
    : super._();
  @override
  EntityEdit rebuild(void Function(EntityEditBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EntityEditBuilder toBuilder() => EntityEditBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EntityEdit &&
        edits == other.edits &&
        writeBack == other.writeBack &&
        lock == other.lock &&
        force == other.force;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, edits.hashCode);
    _$hash = $jc(_$hash, writeBack.hashCode);
    _$hash = $jc(_$hash, lock.hashCode);
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EntityEdit')
          ..add('edits', edits)
          ..add('writeBack', writeBack)
          ..add('lock', lock)
          ..add('force', force))
        .toString();
  }
}

class EntityEditBuilder implements Builder<EntityEdit, EntityEditBuilder> {
  _$EntityEdit? _$v;

  MapBuilder<String, String>? _edits;
  MapBuilder<String, String> get edits =>
      _$this._edits ??= MapBuilder<String, String>();
  set edits(MapBuilder<String, String>? edits) => _$this._edits = edits;

  bool? _writeBack;
  bool? get writeBack => _$this._writeBack;
  set writeBack(bool? writeBack) => _$this._writeBack = writeBack;

  bool? _lock;
  bool? get lock => _$this._lock;
  set lock(bool? lock) => _$this._lock = lock;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  EntityEditBuilder() {
    EntityEdit._defaults(this);
  }

  EntityEditBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _edits = $v.edits.toBuilder();
      _writeBack = $v.writeBack;
      _lock = $v.lock;
      _force = $v.force;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EntityEdit other) {
    _$v = other as _$EntityEdit;
  }

  @override
  void update(void Function(EntityEditBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EntityEdit build() => _build();

  _$EntityEdit _build() {
    _$EntityEdit _$result;
    try {
      _$result =
          _$v ??
          _$EntityEdit._(
            edits: edits.build(),
            writeBack: writeBack,
            lock: lock,
            force: force,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'edits';
        edits.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EntityEdit',
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
