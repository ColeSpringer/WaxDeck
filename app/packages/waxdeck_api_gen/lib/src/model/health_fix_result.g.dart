// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_fix_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HealthFixResult extends HealthFixResult {
  @override
  final int queued;
  @override
  final String? jobPid;
  @override
  final String? taskId;

  factory _$HealthFixResult([void Function(HealthFixResultBuilder)? updates]) =>
      (HealthFixResultBuilder()..update(updates))._build();

  _$HealthFixResult._({required this.queued, this.jobPid, this.taskId})
    : super._();
  @override
  HealthFixResult rebuild(void Function(HealthFixResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthFixResultBuilder toBuilder() => HealthFixResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthFixResult &&
        queued == other.queued &&
        jobPid == other.jobPid &&
        taskId == other.taskId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, queued.hashCode);
    _$hash = $jc(_$hash, jobPid.hashCode);
    _$hash = $jc(_$hash, taskId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthFixResult')
          ..add('queued', queued)
          ..add('jobPid', jobPid)
          ..add('taskId', taskId))
        .toString();
  }
}

class HealthFixResultBuilder
    implements Builder<HealthFixResult, HealthFixResultBuilder> {
  _$HealthFixResult? _$v;

  int? _queued;
  int? get queued => _$this._queued;
  set queued(int? queued) => _$this._queued = queued;

  String? _jobPid;
  String? get jobPid => _$this._jobPid;
  set jobPid(String? jobPid) => _$this._jobPid = jobPid;

  String? _taskId;
  String? get taskId => _$this._taskId;
  set taskId(String? taskId) => _$this._taskId = taskId;

  HealthFixResultBuilder() {
    HealthFixResult._defaults(this);
  }

  HealthFixResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _queued = $v.queued;
      _jobPid = $v.jobPid;
      _taskId = $v.taskId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthFixResult other) {
    _$v = other as _$HealthFixResult;
  }

  @override
  void update(void Function(HealthFixResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthFixResult build() => _build();

  _$HealthFixResult _build() {
    final _$result =
        _$v ??
        _$HealthFixResult._(
          queued: BuiltValueNullFieldError.checkNotNull(
            queued,
            r'HealthFixResult',
            'queued',
          ),
          jobPid: jobPid,
          taskId: taskId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
