// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job_target.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$JobTarget extends JobTarget {
  @override
  final String type;
  @override
  final String pid;
  @override
  final String? name;

  factory _$JobTarget([void Function(JobTargetBuilder)? updates]) =>
      (JobTargetBuilder()..update(updates))._build();

  _$JobTarget._({required this.type, required this.pid, this.name}) : super._();
  @override
  JobTarget rebuild(void Function(JobTargetBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  JobTargetBuilder toBuilder() => JobTargetBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is JobTarget &&
        type == other.type &&
        pid == other.pid &&
        name == other.name;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'JobTarget')
          ..add('type', type)
          ..add('pid', pid)
          ..add('name', name))
        .toString();
  }
}

class JobTargetBuilder implements Builder<JobTarget, JobTargetBuilder> {
  _$JobTarget? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  JobTargetBuilder() {
    JobTarget._defaults(this);
  }

  JobTargetBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _pid = $v.pid;
      _name = $v.name;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(JobTarget other) {
    _$v = other as _$JobTarget;
  }

  @override
  void update(void Function(JobTargetBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  JobTarget build() => _build();

  _$JobTarget _build() {
    final _$result =
        _$v ??
        _$JobTarget._(
          type: BuiltValueNullFieldError.checkNotNull(
            type,
            r'JobTarget',
            'type',
          ),
          pid: BuiltValueNullFieldError.checkNotNull(pid, r'JobTarget', 'pid'),
          name: name,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
