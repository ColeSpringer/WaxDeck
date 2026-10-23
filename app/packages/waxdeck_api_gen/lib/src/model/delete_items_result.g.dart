// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delete_items_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DeleteItemsResult extends DeleteItemsResult {
  @override
  final bool applied;
  @override
  final String mode;
  @override
  final BuiltList<DeletePlanEntry> entries;
  @override
  final BuiltList<String>? warnings;
  @override
  final int? trashed;
  @override
  final int? deleted;
  @override
  final int? failed;
  @override
  final int? dirsPruned;
  @override
  final int? reclaimedBytes;

  factory _$DeleteItemsResult([
    void Function(DeleteItemsResultBuilder)? updates,
  ]) => (DeleteItemsResultBuilder()..update(updates))._build();

  _$DeleteItemsResult._({
    required this.applied,
    required this.mode,
    required this.entries,
    this.warnings,
    this.trashed,
    this.deleted,
    this.failed,
    this.dirsPruned,
    this.reclaimedBytes,
  }) : super._();
  @override
  DeleteItemsResult rebuild(void Function(DeleteItemsResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DeleteItemsResultBuilder toBuilder() =>
      DeleteItemsResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DeleteItemsResult &&
        applied == other.applied &&
        mode == other.mode &&
        entries == other.entries &&
        warnings == other.warnings &&
        trashed == other.trashed &&
        deleted == other.deleted &&
        failed == other.failed &&
        dirsPruned == other.dirsPruned &&
        reclaimedBytes == other.reclaimedBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, applied.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jc(_$hash, warnings.hashCode);
    _$hash = $jc(_$hash, trashed.hashCode);
    _$hash = $jc(_$hash, deleted.hashCode);
    _$hash = $jc(_$hash, failed.hashCode);
    _$hash = $jc(_$hash, dirsPruned.hashCode);
    _$hash = $jc(_$hash, reclaimedBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DeleteItemsResult')
          ..add('applied', applied)
          ..add('mode', mode)
          ..add('entries', entries)
          ..add('warnings', warnings)
          ..add('trashed', trashed)
          ..add('deleted', deleted)
          ..add('failed', failed)
          ..add('dirsPruned', dirsPruned)
          ..add('reclaimedBytes', reclaimedBytes))
        .toString();
  }
}

class DeleteItemsResultBuilder
    implements Builder<DeleteItemsResult, DeleteItemsResultBuilder> {
  _$DeleteItemsResult? _$v;

  bool? _applied;
  bool? get applied => _$this._applied;
  set applied(bool? applied) => _$this._applied = applied;

  String? _mode;
  String? get mode => _$this._mode;
  set mode(String? mode) => _$this._mode = mode;

  ListBuilder<DeletePlanEntry>? _entries;
  ListBuilder<DeletePlanEntry> get entries =>
      _$this._entries ??= ListBuilder<DeletePlanEntry>();
  set entries(ListBuilder<DeletePlanEntry>? entries) =>
      _$this._entries = entries;

  ListBuilder<String>? _warnings;
  ListBuilder<String> get warnings =>
      _$this._warnings ??= ListBuilder<String>();
  set warnings(ListBuilder<String>? warnings) => _$this._warnings = warnings;

  int? _trashed;
  int? get trashed => _$this._trashed;
  set trashed(int? trashed) => _$this._trashed = trashed;

  int? _deleted;
  int? get deleted => _$this._deleted;
  set deleted(int? deleted) => _$this._deleted = deleted;

  int? _failed;
  int? get failed => _$this._failed;
  set failed(int? failed) => _$this._failed = failed;

  int? _dirsPruned;
  int? get dirsPruned => _$this._dirsPruned;
  set dirsPruned(int? dirsPruned) => _$this._dirsPruned = dirsPruned;

  int? _reclaimedBytes;
  int? get reclaimedBytes => _$this._reclaimedBytes;
  set reclaimedBytes(int? reclaimedBytes) =>
      _$this._reclaimedBytes = reclaimedBytes;

  DeleteItemsResultBuilder() {
    DeleteItemsResult._defaults(this);
  }

  DeleteItemsResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _applied = $v.applied;
      _mode = $v.mode;
      _entries = $v.entries.toBuilder();
      _warnings = $v.warnings?.toBuilder();
      _trashed = $v.trashed;
      _deleted = $v.deleted;
      _failed = $v.failed;
      _dirsPruned = $v.dirsPruned;
      _reclaimedBytes = $v.reclaimedBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DeleteItemsResult other) {
    _$v = other as _$DeleteItemsResult;
  }

  @override
  void update(void Function(DeleteItemsResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DeleteItemsResult build() => _build();

  _$DeleteItemsResult _build() {
    _$DeleteItemsResult _$result;
    try {
      _$result =
          _$v ??
          _$DeleteItemsResult._(
            applied: BuiltValueNullFieldError.checkNotNull(
              applied,
              r'DeleteItemsResult',
              'applied',
            ),
            mode: BuiltValueNullFieldError.checkNotNull(
              mode,
              r'DeleteItemsResult',
              'mode',
            ),
            entries: entries.build(),
            warnings: _warnings?.build(),
            trashed: trashed,
            deleted: deleted,
            failed: failed,
            dirsPruned: dirsPruned,
            reclaimedBytes: reclaimedBytes,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
        _$failedField = 'warnings';
        _warnings?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'DeleteItemsResult',
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
