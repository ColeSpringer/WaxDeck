// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bulk_edit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BulkEdit extends BulkEdit {
  @override
  final BuiltList<String> itemPids;
  @override
  final BuiltMap<String, String> fields;
  @override
  final bool? writeBack;
  @override
  final bool? skipLocked;
  @override
  final bool? force;

  factory _$BulkEdit([void Function(BulkEditBuilder)? updates]) =>
      (BulkEditBuilder()..update(updates))._build();

  _$BulkEdit._({
    required this.itemPids,
    required this.fields,
    this.writeBack,
    this.skipLocked,
    this.force,
  }) : super._();
  @override
  BulkEdit rebuild(void Function(BulkEditBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BulkEditBuilder toBuilder() => BulkEditBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BulkEdit &&
        itemPids == other.itemPids &&
        fields == other.fields &&
        writeBack == other.writeBack &&
        skipLocked == other.skipLocked &&
        force == other.force;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, itemPids.hashCode);
    _$hash = $jc(_$hash, fields.hashCode);
    _$hash = $jc(_$hash, writeBack.hashCode);
    _$hash = $jc(_$hash, skipLocked.hashCode);
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BulkEdit')
          ..add('itemPids', itemPids)
          ..add('fields', fields)
          ..add('writeBack', writeBack)
          ..add('skipLocked', skipLocked)
          ..add('force', force))
        .toString();
  }
}

class BulkEditBuilder implements Builder<BulkEdit, BulkEditBuilder> {
  _$BulkEdit? _$v;

  ListBuilder<String>? _itemPids;
  ListBuilder<String> get itemPids =>
      _$this._itemPids ??= ListBuilder<String>();
  set itemPids(ListBuilder<String>? itemPids) => _$this._itemPids = itemPids;

  MapBuilder<String, String>? _fields;
  MapBuilder<String, String> get fields =>
      _$this._fields ??= MapBuilder<String, String>();
  set fields(MapBuilder<String, String>? fields) => _$this._fields = fields;

  bool? _writeBack;
  bool? get writeBack => _$this._writeBack;
  set writeBack(bool? writeBack) => _$this._writeBack = writeBack;

  bool? _skipLocked;
  bool? get skipLocked => _$this._skipLocked;
  set skipLocked(bool? skipLocked) => _$this._skipLocked = skipLocked;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  BulkEditBuilder() {
    BulkEdit._defaults(this);
  }

  BulkEditBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _itemPids = $v.itemPids.toBuilder();
      _fields = $v.fields.toBuilder();
      _writeBack = $v.writeBack;
      _skipLocked = $v.skipLocked;
      _force = $v.force;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BulkEdit other) {
    _$v = other as _$BulkEdit;
  }

  @override
  void update(void Function(BulkEditBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BulkEdit build() => _build();

  _$BulkEdit _build() {
    _$BulkEdit _$result;
    try {
      _$result =
          _$v ??
          _$BulkEdit._(
            itemPids: itemPids.build(),
            fields: fields.build(),
            writeBack: writeBack,
            skipLocked: skipLocked,
            force: force,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'itemPids';
        itemPids.build();
        _$failedField = 'fields';
        fields.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'BulkEdit',
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
