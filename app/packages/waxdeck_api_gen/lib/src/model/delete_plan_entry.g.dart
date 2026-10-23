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
  @override
  final BuiltList<DeletePlanFile>? fileList;
  @override
  final BuiltList<String>? paths;
  @override
  final int? failed;
  @override
  final String? error;
  @override
  final bool? itemSurvives;

  factory _$DeletePlanEntry([void Function(DeletePlanEntryBuilder)? updates]) =>
      (DeletePlanEntryBuilder()..update(updates))._build();

  _$DeletePlanEntry._({
    required this.pid,
    this.name,
    required this.files,
    required this.bytes,
    this.fileList,
    this.paths,
    this.failed,
    this.error,
    this.itemSurvives,
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
        bytes == other.bytes &&
        fileList == other.fileList &&
        paths == other.paths &&
        failed == other.failed &&
        error == other.error &&
        itemSurvives == other.itemSurvives;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, files.hashCode);
    _$hash = $jc(_$hash, bytes.hashCode);
    _$hash = $jc(_$hash, fileList.hashCode);
    _$hash = $jc(_$hash, paths.hashCode);
    _$hash = $jc(_$hash, failed.hashCode);
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jc(_$hash, itemSurvives.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DeletePlanEntry')
          ..add('pid', pid)
          ..add('name', name)
          ..add('files', files)
          ..add('bytes', bytes)
          ..add('fileList', fileList)
          ..add('paths', paths)
          ..add('failed', failed)
          ..add('error', error)
          ..add('itemSurvives', itemSurvives))
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

  ListBuilder<DeletePlanFile>? _fileList;
  ListBuilder<DeletePlanFile> get fileList =>
      _$this._fileList ??= ListBuilder<DeletePlanFile>();
  set fileList(ListBuilder<DeletePlanFile>? fileList) =>
      _$this._fileList = fileList;

  ListBuilder<String>? _paths;
  ListBuilder<String> get paths => _$this._paths ??= ListBuilder<String>();
  set paths(ListBuilder<String>? paths) => _$this._paths = paths;

  int? _failed;
  int? get failed => _$this._failed;
  set failed(int? failed) => _$this._failed = failed;

  String? _error;
  String? get error => _$this._error;
  set error(String? error) => _$this._error = error;

  bool? _itemSurvives;
  bool? get itemSurvives => _$this._itemSurvives;
  set itemSurvives(bool? itemSurvives) => _$this._itemSurvives = itemSurvives;

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
      _fileList = $v.fileList?.toBuilder();
      _paths = $v.paths?.toBuilder();
      _failed = $v.failed;
      _error = $v.error;
      _itemSurvives = $v.itemSurvives;
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
    _$DeletePlanEntry _$result;
    try {
      _$result =
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
            fileList: _fileList?.build(),
            paths: _paths?.build(),
            failed: failed,
            error: error,
            itemSurvives: itemSurvives,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'fileList';
        _fileList?.build();
        _$failedField = 'paths';
        _paths?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'DeletePlanEntry',
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
