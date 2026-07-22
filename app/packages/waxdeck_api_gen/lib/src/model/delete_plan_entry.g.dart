// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delete_plan_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DeletePlanEntry extends DeletePlanEntry {
  @override
  final String pid;
  @override
  final String? name;
  @override
  final int files;
  @override
  final int bytes;

  factory _$DeletePlanEntry([void Function(DeletePlanEntryBuilder)? updates]) =>
      (DeletePlanEntryBuilder()..update(updates))._build();

  _$DeletePlanEntry._({
    required this.pid,
    this.name,
    required this.files,
    required this.bytes,
  }) : super._();
  @override
  DeletePlanEntry rebuild(void Function(DeletePlanEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DeletePlanEntryBuilder toBuilder() => DeletePlanEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DeletePlanEntry &&
        pid == other.pid &&
        name == other.name &&
        files == other.files &&
        bytes == other.bytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, files.hashCode);
    _$hash = $jc(_$hash, bytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DeletePlanEntry')
          ..add('pid', pid)
          ..add('name', name)
          ..add('files', files)
          ..add('bytes', bytes))
        .toString();
  }
}

class DeletePlanEntryBuilder
    implements Builder<DeletePlanEntry, DeletePlanEntryBuilder> {
  _$DeletePlanEntry? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _files;
  int? get files => _$this._files;
  set files(int? files) => _$this._files = files;

  int? _bytes;
  int? get bytes => _$this._bytes;
  set bytes(int? bytes) => _$this._bytes = bytes;

  DeletePlanEntryBuilder() {
    DeletePlanEntry._defaults(this);
  }

  DeletePlanEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _name = $v.name;
      _files = $v.files;
      _bytes = $v.bytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DeletePlanEntry other) {
    _$v = other as _$DeletePlanEntry;
  }

  @override
  void update(void Function(DeletePlanEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DeletePlanEntry build() => _build();

  _$DeletePlanEntry _build() {
    final _$result =
        _$v ??
        _$DeletePlanEntry._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'DeletePlanEntry',
            'pid',
          ),
          name: name,
          files: BuiltValueNullFieldError.checkNotNull(
            files,
            r'DeletePlanEntry',
            'files',
          ),
          bytes: BuiltValueNullFieldError.checkNotNull(
            bytes,
            r'DeletePlanEntry',
            'bytes',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
