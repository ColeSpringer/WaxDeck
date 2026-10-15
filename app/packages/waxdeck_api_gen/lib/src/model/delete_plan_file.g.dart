// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delete_plan_file.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DeletePlanFile extends DeletePlanFile {
  @override
  final String filePid;
  @override
  final String name;
  @override
  final int? sizeBytes;
  @override
  final String role;

  factory _$DeletePlanFile([void Function(DeletePlanFileBuilder)? updates]) =>
      (DeletePlanFileBuilder()..update(updates))._build();

  _$DeletePlanFile._({
    required this.filePid,
    required this.name,
    this.sizeBytes,
    required this.role,
  }) : super._();
  @override
  DeletePlanFile rebuild(void Function(DeletePlanFileBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DeletePlanFileBuilder toBuilder() => DeletePlanFileBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DeletePlanFile &&
        filePid == other.filePid &&
        name == other.name &&
        sizeBytes == other.sizeBytes &&
        role == other.role;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, filePid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DeletePlanFile')
          ..add('filePid', filePid)
          ..add('name', name)
          ..add('sizeBytes', sizeBytes)
          ..add('role', role))
        .toString();
  }
}

class DeletePlanFileBuilder
    implements Builder<DeletePlanFile, DeletePlanFileBuilder> {
  _$DeletePlanFile? _$v;

  String? _filePid;
  String? get filePid => _$this._filePid;
  set filePid(String? filePid) => _$this._filePid = filePid;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  String? _role;
  String? get role => _$this._role;
  set role(String? role) => _$this._role = role;

  DeletePlanFileBuilder() {
    DeletePlanFile._defaults(this);
  }

  DeletePlanFileBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _filePid = $v.filePid;
      _name = $v.name;
      _sizeBytes = $v.sizeBytes;
      _role = $v.role;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DeletePlanFile other) {
    _$v = other as _$DeletePlanFile;
  }

  @override
  void update(void Function(DeletePlanFileBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DeletePlanFile build() => _build();

  _$DeletePlanFile _build() {
    final _$result =
        _$v ??
        _$DeletePlanFile._(
          filePid: BuiltValueNullFieldError.checkNotNull(
            filePid,
            r'DeletePlanFile',
            'filePid',
          ),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'DeletePlanFile',
            'name',
          ),
          sizeBytes: sizeBytes,
          role: BuiltValueNullFieldError.checkNotNull(
            role,
            r'DeletePlanFile',
            'role',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
