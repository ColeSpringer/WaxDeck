// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Job extends Job {
  @override
  final String pid;
  @override
  final String kind;
  @override
  final String state;
  @override
  final double? progress;
  @override
  final String? message;
  @override
  final String? error;
  @override
  final DateTime? startedAt;
  @override
  final DateTime? finishedAt;
  @override
  final BuiltMap<String, JsonObject?>? result;

  factory _$Job([void Function(JobBuilder)? updates]) =>
      (JobBuilder()..update(updates))._build();

  _$Job._({
    required this.pid,
    required this.kind,
    required this.state,
    this.progress,
    this.message,
    this.error,
    this.startedAt,
    this.finishedAt,
    this.result,
  }) : super._();
  @override
  Job rebuild(void Function(JobBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  JobBuilder toBuilder() => JobBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Job &&
        pid == other.pid &&
        kind == other.kind &&
        state == other.state &&
        progress == other.progress &&
        message == other.message &&
        error == other.error &&
        startedAt == other.startedAt &&
        finishedAt == other.finishedAt &&
        result == other.result;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, progress.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jc(_$hash, startedAt.hashCode);
    _$hash = $jc(_$hash, finishedAt.hashCode);
    _$hash = $jc(_$hash, result.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Job')
          ..add('pid', pid)
          ..add('kind', kind)
          ..add('state', state)
          ..add('progress', progress)
          ..add('message', message)
          ..add('error', error)
          ..add('startedAt', startedAt)
          ..add('finishedAt', finishedAt)
          ..add('result', result))
        .toString();
  }
}

class JobBuilder implements Builder<Job, JobBuilder> {
  _$Job? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  String? _state;
  String? get state => _$this._state;
  set state(String? state) => _$this._state = state;

  double? _progress;
  double? get progress => _$this._progress;
  set progress(double? progress) => _$this._progress = progress;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  String? _error;
  String? get error => _$this._error;
  set error(String? error) => _$this._error = error;

  DateTime? _startedAt;
  DateTime? get startedAt => _$this._startedAt;
  set startedAt(DateTime? startedAt) => _$this._startedAt = startedAt;

  DateTime? _finishedAt;
  DateTime? get finishedAt => _$this._finishedAt;
  set finishedAt(DateTime? finishedAt) => _$this._finishedAt = finishedAt;

  MapBuilder<String, JsonObject?>? _result;
  MapBuilder<String, JsonObject?> get result =>
      _$this._result ??= MapBuilder<String, JsonObject?>();
  set result(MapBuilder<String, JsonObject?>? result) =>
      _$this._result = result;

  JobBuilder() {
    Job._defaults(this);
  }

  JobBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _kind = $v.kind;
      _state = $v.state;
      _progress = $v.progress;
      _message = $v.message;
      _error = $v.error;
      _startedAt = $v.startedAt;
      _finishedAt = $v.finishedAt;
      _result = $v.result?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Job other) {
    _$v = other as _$Job;
  }

  @override
  void update(void Function(JobBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Job build() => _build();

  _$Job _build() {
    _$Job _$result;
    try {
      _$result =
          _$v ??
          _$Job._(
            pid: BuiltValueNullFieldError.checkNotNull(pid, r'Job', 'pid'),
            kind: BuiltValueNullFieldError.checkNotNull(kind, r'Job', 'kind'),
            state: BuiltValueNullFieldError.checkNotNull(
              state,
              r'Job',
              'state',
            ),
            progress: progress,
            message: message,
            error: error,
            startedAt: startedAt,
            finishedAt: finishedAt,
            result: _result?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'result';
        _result?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'Job', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
