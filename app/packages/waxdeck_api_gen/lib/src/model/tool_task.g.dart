// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tool_task.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ToolTask extends ToolTask {
  @override
  final String id;
  @override
  final String type;
  @override
  final String state;
  @override
  final String? itemPid;
  @override
  final double? progressPct;
  @override
  final String? error;
  @override
  final BuiltList<String>? resultPids;
  @override
  final DateTime createdAt;
  @override
  final DateTime? finishedAt;

  factory _$ToolTask([void Function(ToolTaskBuilder)? updates]) =>
      (ToolTaskBuilder()..update(updates))._build();

  _$ToolTask._({
    required this.id,
    required this.type,
    required this.state,
    this.itemPid,
    this.progressPct,
    this.error,
    this.resultPids,
    required this.createdAt,
    this.finishedAt,
  }) : super._();
  @override
  ToolTask rebuild(void Function(ToolTaskBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ToolTaskBuilder toBuilder() => ToolTaskBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ToolTask &&
        id == other.id &&
        type == other.type &&
        state == other.state &&
        itemPid == other.itemPid &&
        progressPct == other.progressPct &&
        error == other.error &&
        resultPids == other.resultPids &&
        createdAt == other.createdAt &&
        finishedAt == other.finishedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, itemPid.hashCode);
    _$hash = $jc(_$hash, progressPct.hashCode);
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jc(_$hash, resultPids.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, finishedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ToolTask')
          ..add('id', id)
          ..add('type', type)
          ..add('state', state)
          ..add('itemPid', itemPid)
          ..add('progressPct', progressPct)
          ..add('error', error)
          ..add('resultPids', resultPids)
          ..add('createdAt', createdAt)
          ..add('finishedAt', finishedAt))
        .toString();
  }
}

class ToolTaskBuilder implements Builder<ToolTask, ToolTaskBuilder> {
  _$ToolTask? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  String? _state;
  String? get state => _$this._state;
  set state(String? state) => _$this._state = state;

  String? _itemPid;
  String? get itemPid => _$this._itemPid;
  set itemPid(String? itemPid) => _$this._itemPid = itemPid;

  double? _progressPct;
  double? get progressPct => _$this._progressPct;
  set progressPct(double? progressPct) => _$this._progressPct = progressPct;

  String? _error;
  String? get error => _$this._error;
  set error(String? error) => _$this._error = error;

  ListBuilder<String>? _resultPids;
  ListBuilder<String> get resultPids =>
      _$this._resultPids ??= ListBuilder<String>();
  set resultPids(ListBuilder<String>? resultPids) =>
      _$this._resultPids = resultPids;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _finishedAt;
  DateTime? get finishedAt => _$this._finishedAt;
  set finishedAt(DateTime? finishedAt) => _$this._finishedAt = finishedAt;

  ToolTaskBuilder() {
    ToolTask._defaults(this);
  }

  ToolTaskBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _type = $v.type;
      _state = $v.state;
      _itemPid = $v.itemPid;
      _progressPct = $v.progressPct;
      _error = $v.error;
      _resultPids = $v.resultPids?.toBuilder();
      _createdAt = $v.createdAt;
      _finishedAt = $v.finishedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ToolTask other) {
    _$v = other as _$ToolTask;
  }

  @override
  void update(void Function(ToolTaskBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ToolTask build() => _build();

  _$ToolTask _build() {
    _$ToolTask _$result;
    try {
      _$result =
          _$v ??
          _$ToolTask._(
            id: BuiltValueNullFieldError.checkNotNull(id, r'ToolTask', 'id'),
            type: BuiltValueNullFieldError.checkNotNull(
              type,
              r'ToolTask',
              'type',
            ),
            state: BuiltValueNullFieldError.checkNotNull(
              state,
              r'ToolTask',
              'state',
            ),
            itemPid: itemPid,
            progressPct: progressPct,
            error: error,
            resultPids: _resultPids?.build(),
            createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt,
              r'ToolTask',
              'createdAt',
            ),
            finishedAt: finishedAt,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'resultPids';
        _resultPids?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ToolTask',
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
