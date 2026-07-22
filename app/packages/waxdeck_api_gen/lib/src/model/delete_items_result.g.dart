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

  factory _$DeleteItemsResult([
    void Function(DeleteItemsResultBuilder)? updates,
  ]) => (DeleteItemsResultBuilder()..update(updates))._build();

  _$DeleteItemsResult._({
    required this.applied,
    required this.mode,
    required this.entries,
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
        entries == other.entries;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, applied.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DeleteItemsResult')
          ..add('applied', applied)
          ..add('mode', mode)
          ..add('entries', entries))
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

  DeleteItemsResultBuilder() {
    DeleteItemsResult._defaults(this);
  }

  DeleteItemsResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _applied = $v.applied;
      _mode = $v.mode;
      _entries = $v.entries.toBuilder();
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
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
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
