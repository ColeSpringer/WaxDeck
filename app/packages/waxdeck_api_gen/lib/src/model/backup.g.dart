// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Backup extends Backup {
  @override
  final String id;
  @override
  final String state;
  @override
  final String trigger;
  @override
  final String fileName;
  @override
  final int? sizeBytes;
  @override
  final String? error;
  @override
  final DateTime createdAt;
  @override
  final DateTime? finishedAt;

  factory _$Backup([void Function(BackupBuilder)? updates]) =>
      (BackupBuilder()..update(updates))._build();

  _$Backup._({
    required this.id,
    required this.state,
    required this.trigger,
    required this.fileName,
    this.sizeBytes,
    this.error,
    required this.createdAt,
    this.finishedAt,
  }) : super._();
  @override
  Backup rebuild(void Function(BackupBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BackupBuilder toBuilder() => BackupBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Backup &&
        id == other.id &&
        state == other.state &&
        trigger == other.trigger &&
        fileName == other.fileName &&
        sizeBytes == other.sizeBytes &&
        error == other.error &&
        createdAt == other.createdAt &&
        finishedAt == other.finishedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, trigger.hashCode);
    _$hash = $jc(_$hash, fileName.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, finishedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Backup')
          ..add('id', id)
          ..add('state', state)
          ..add('trigger', trigger)
          ..add('fileName', fileName)
          ..add('sizeBytes', sizeBytes)
          ..add('error', error)
          ..add('createdAt', createdAt)
          ..add('finishedAt', finishedAt))
        .toString();
  }
}

class BackupBuilder implements Builder<Backup, BackupBuilder> {
  _$Backup? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _state;
  String? get state => _$this._state;
  set state(String? state) => _$this._state = state;

  String? _trigger;
  String? get trigger => _$this._trigger;
  set trigger(String? trigger) => _$this._trigger = trigger;

  String? _fileName;
  String? get fileName => _$this._fileName;
  set fileName(String? fileName) => _$this._fileName = fileName;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  String? _error;
  String? get error => _$this._error;
  set error(String? error) => _$this._error = error;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _finishedAt;
  DateTime? get finishedAt => _$this._finishedAt;
  set finishedAt(DateTime? finishedAt) => _$this._finishedAt = finishedAt;

  BackupBuilder() {
    Backup._defaults(this);
  }

  BackupBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _state = $v.state;
      _trigger = $v.trigger;
      _fileName = $v.fileName;
      _sizeBytes = $v.sizeBytes;
      _error = $v.error;
      _createdAt = $v.createdAt;
      _finishedAt = $v.finishedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Backup other) {
    _$v = other as _$Backup;
  }

  @override
  void update(void Function(BackupBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Backup build() => _build();

  _$Backup _build() {
    final _$result =
        _$v ??
        _$Backup._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'Backup', 'id'),
          state: BuiltValueNullFieldError.checkNotNull(
            state,
            r'Backup',
            'state',
          ),
          trigger: BuiltValueNullFieldError.checkNotNull(
            trigger,
            r'Backup',
            'trigger',
          ),
          fileName: BuiltValueNullFieldError.checkNotNull(
            fileName,
            r'Backup',
            'fileName',
          ),
          sizeBytes: sizeBytes,
          error: error,
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'Backup',
            'createdAt',
          ),
          finishedAt: finishedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
