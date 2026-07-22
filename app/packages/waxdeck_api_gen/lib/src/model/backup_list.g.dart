// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BackupList extends BackupList {
  @override
  final BuiltList<Backup> backups;

  factory _$BackupList([void Function(BackupListBuilder)? updates]) =>
      (BackupListBuilder()..update(updates))._build();

  _$BackupList._({required this.backups}) : super._();
  @override
  BackupList rebuild(void Function(BackupListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BackupListBuilder toBuilder() => BackupListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BackupList && backups == other.backups;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, backups.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'BackupList',
    )..add('backups', backups)).toString();
  }
}

class BackupListBuilder implements Builder<BackupList, BackupListBuilder> {
  _$BackupList? _$v;

  ListBuilder<Backup>? _backups;
  ListBuilder<Backup> get backups => _$this._backups ??= ListBuilder<Backup>();
  set backups(ListBuilder<Backup>? backups) => _$this._backups = backups;

  BackupListBuilder() {
    BackupList._defaults(this);
  }

  BackupListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _backups = $v.backups.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BackupList other) {
    _$v = other as _$BackupList;
  }

  @override
  void update(void Function(BackupListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BackupList build() => _build();

  _$BackupList _build() {
    _$BackupList _$result;
    try {
      _$result = _$v ?? _$BackupList._(backups: backups.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'backups';
        backups.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'BackupList',
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
