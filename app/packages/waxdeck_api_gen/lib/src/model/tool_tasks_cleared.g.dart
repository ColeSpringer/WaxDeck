// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tool_tasks_cleared.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ToolTasksCleared extends ToolTasksCleared {
  @override
  final int deleted;
  @override
  final int kept;

  factory _$ToolTasksCleared([
    void Function(ToolTasksClearedBuilder)? updates,
  ]) => (ToolTasksClearedBuilder()..update(updates))._build();

  _$ToolTasksCleared._({required this.deleted, required this.kept}) : super._();
  @override
  ToolTasksCleared rebuild(void Function(ToolTasksClearedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ToolTasksClearedBuilder toBuilder() =>
      ToolTasksClearedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ToolTasksCleared &&
        deleted == other.deleted &&
        kept == other.kept;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, deleted.hashCode);
    _$hash = $jc(_$hash, kept.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ToolTasksCleared')
          ..add('deleted', deleted)
          ..add('kept', kept))
        .toString();
  }
}

class ToolTasksClearedBuilder
    implements Builder<ToolTasksCleared, ToolTasksClearedBuilder> {
  _$ToolTasksCleared? _$v;

  int? _deleted;
  int? get deleted => _$this._deleted;
  set deleted(int? deleted) => _$this._deleted = deleted;

  int? _kept;
  int? get kept => _$this._kept;
  set kept(int? kept) => _$this._kept = kept;

  ToolTasksClearedBuilder() {
    ToolTasksCleared._defaults(this);
  }

  ToolTasksClearedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _deleted = $v.deleted;
      _kept = $v.kept;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ToolTasksCleared other) {
    _$v = other as _$ToolTasksCleared;
  }

  @override
  void update(void Function(ToolTasksClearedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ToolTasksCleared build() => _build();

  _$ToolTasksCleared _build() {
    final _$result =
        _$v ??
        _$ToolTasksCleared._(
          deleted: BuiltValueNullFieldError.checkNotNull(
            deleted,
            r'ToolTasksCleared',
            'deleted',
          ),
          kept: BuiltValueNullFieldError.checkNotNull(
            kept,
            r'ToolTasksCleared',
            'kept',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
