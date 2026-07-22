// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trash_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TrashEntry extends TrashEntry {
  @override
  final String id;
  @override
  final String? itemPid;
  @override
  final String name;
  @override
  final String reason;
  @override
  final int sizeBytes;
  @override
  final DateTime trashedAt;
  @override
  final DateTime? restoredAt;

  factory _$TrashEntry([void Function(TrashEntryBuilder)? updates]) =>
      (TrashEntryBuilder()..update(updates))._build();

  _$TrashEntry._({
    required this.id,
    this.itemPid,
    required this.name,
    required this.reason,
    required this.sizeBytes,
    required this.trashedAt,
    this.restoredAt,
  }) : super._();
  @override
  TrashEntry rebuild(void Function(TrashEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TrashEntryBuilder toBuilder() => TrashEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TrashEntry &&
        id == other.id &&
        itemPid == other.itemPid &&
        name == other.name &&
        reason == other.reason &&
        sizeBytes == other.sizeBytes &&
        trashedAt == other.trashedAt &&
        restoredAt == other.restoredAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, itemPid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, trashedAt.hashCode);
    _$hash = $jc(_$hash, restoredAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TrashEntry')
          ..add('id', id)
          ..add('itemPid', itemPid)
          ..add('name', name)
          ..add('reason', reason)
          ..add('sizeBytes', sizeBytes)
          ..add('trashedAt', trashedAt)
          ..add('restoredAt', restoredAt))
        .toString();
  }
}

class TrashEntryBuilder implements Builder<TrashEntry, TrashEntryBuilder> {
  _$TrashEntry? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _itemPid;
  String? get itemPid => _$this._itemPid;
  set itemPid(String? itemPid) => _$this._itemPid = itemPid;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _reason;
  String? get reason => _$this._reason;
  set reason(String? reason) => _$this._reason = reason;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  DateTime? _trashedAt;
  DateTime? get trashedAt => _$this._trashedAt;
  set trashedAt(DateTime? trashedAt) => _$this._trashedAt = trashedAt;

  DateTime? _restoredAt;
  DateTime? get restoredAt => _$this._restoredAt;
  set restoredAt(DateTime? restoredAt) => _$this._restoredAt = restoredAt;

  TrashEntryBuilder() {
    TrashEntry._defaults(this);
  }

  TrashEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _itemPid = $v.itemPid;
      _name = $v.name;
      _reason = $v.reason;
      _sizeBytes = $v.sizeBytes;
      _trashedAt = $v.trashedAt;
      _restoredAt = $v.restoredAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TrashEntry other) {
    _$v = other as _$TrashEntry;
  }

  @override
  void update(void Function(TrashEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TrashEntry build() => _build();

  _$TrashEntry _build() {
    final _$result =
        _$v ??
        _$TrashEntry._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'TrashEntry', 'id'),
          itemPid: itemPid,
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'TrashEntry',
            'name',
          ),
          reason: BuiltValueNullFieldError.checkNotNull(
            reason,
            r'TrashEntry',
            'reason',
          ),
          sizeBytes: BuiltValueNullFieldError.checkNotNull(
            sizeBytes,
            r'TrashEntry',
            'sizeBytes',
          ),
          trashedAt: BuiltValueNullFieldError.checkNotNull(
            trashedAt,
            r'TrashEntry',
            'trashedAt',
          ),
          restoredAt: restoredAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
