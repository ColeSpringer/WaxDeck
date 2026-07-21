// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata_edit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MetadataEdit extends MetadataEdit {
  @override
  final BuiltMap<String, String> fields;
  @override
  final bool? writeBack;
  @override
  final bool? lock;
  @override
  final bool? force;

  factory _$MetadataEdit([void Function(MetadataEditBuilder)? updates]) =>
      (MetadataEditBuilder()..update(updates))._build();

  _$MetadataEdit._({
    required this.fields,
    this.writeBack,
    this.lock,
    this.force,
  }) : super._();
  @override
  MetadataEdit rebuild(void Function(MetadataEditBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MetadataEditBuilder toBuilder() => MetadataEditBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MetadataEdit &&
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
    return (newBuiltValueToStringHelper(r'MetadataEdit')
          ..add('fields', fields)
          ..add('writeBack', writeBack)
          ..add('lock', lock)
          ..add('force', force))
        .toString();
  }
}

class MetadataEditBuilder
    implements Builder<MetadataEdit, MetadataEditBuilder> {
  _$MetadataEdit? _$v;

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

  MetadataEditBuilder() {
    MetadataEdit._defaults(this);
  }

  MetadataEditBuilder get _$this {
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
  void replace(MetadataEdit other) {
    _$v = other as _$MetadataEdit;
  }

  @override
  void update(void Function(MetadataEditBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MetadataEdit build() => _build();

  _$MetadataEdit _build() {
    _$MetadataEdit _$result;
    try {
      _$result =
          _$v ??
          _$MetadataEdit._(
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
          r'MetadataEdit',
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
