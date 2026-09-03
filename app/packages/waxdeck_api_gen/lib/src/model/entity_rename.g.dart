// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_rename.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EntityRename extends EntityRename {
  @override
  final BuiltMap<String, String> fields;
  @override
  final bool? writeBack;
  @override
  final bool? lock;
  @override
  final bool? force;

  factory _$EntityRename([void Function(EntityRenameBuilder)? updates]) =>
      (EntityRenameBuilder()..update(updates))._build();

  _$EntityRename._({
    required this.fields,
    this.writeBack,
    this.lock,
    this.force,
  }) : super._();
  @override
  EntityRename rebuild(void Function(EntityRenameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EntityRenameBuilder toBuilder() => EntityRenameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EntityRename &&
        fields == other.fields &&
        writeBack == other.writeBack &&
        lock == other.lock &&
        force == other.force;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, fields.hashCode);
    _$hash = $jc(_$hash, writeBack.hashCode);
    _$hash = $jc(_$hash, lock.hashCode);
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EntityRename')
          ..add('fields', fields)
          ..add('writeBack', writeBack)
          ..add('lock', lock)
          ..add('force', force))
        .toString();
  }
}

class EntityRenameBuilder
    implements Builder<EntityRename, EntityRenameBuilder> {
  _$EntityRename? _$v;

  MapBuilder<String, String>? _fields;
  MapBuilder<String, String> get fields =>
      _$this._fields ??= MapBuilder<String, String>();
  set fields(MapBuilder<String, String>? fields) => _$this._fields = fields;

  bool? _writeBack;
  bool? get writeBack => _$this._writeBack;
  set writeBack(bool? writeBack) => _$this._writeBack = writeBack;

  bool? _lock;
  bool? get lock => _$this._lock;
  set lock(bool? lock) => _$this._lock = lock;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  EntityRenameBuilder() {
    EntityRename._defaults(this);
  }

  EntityRenameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _fields = $v.fields.toBuilder();
      _writeBack = $v.writeBack;
      _lock = $v.lock;
      _force = $v.force;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EntityRename other) {
    _$v = other as _$EntityRename;
  }

  @override
  void update(void Function(EntityRenameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EntityRename build() => _build();

  _$EntityRename _build() {
    _$EntityRename _$result;
    try {
      _$result =
          _$v ??
          _$EntityRename._(
            fields: fields.build(),
            writeBack: writeBack,
            lock: lock,
            force: force,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'fields';
        fields.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EntityRename',
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
