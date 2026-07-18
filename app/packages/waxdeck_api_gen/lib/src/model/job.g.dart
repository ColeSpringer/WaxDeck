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

  factory _$Job([void Function(JobBuilder)? updates]) =>
      (JobBuilder()..update(updates))._build();

  _$Job._({
    required this.pid,
    required this.kind,
    required this.state,
    this.progress,
    this.message,
    this.error,
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
        error == other.error;
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
          ..add('error', error))
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
    final _$result =
        _$v ??
        _$Job._(
          pid: BuiltValueNullFieldError.checkNotNull(pid, r'Job', 'pid'),
          kind: BuiltValueNullFieldError.checkNotNull(kind, r'Job', 'kind'),
          state: BuiltValueNullFieldError.checkNotNull(state, r'Job', 'state'),
          progress: progress,
          message: message,
          error: error,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
