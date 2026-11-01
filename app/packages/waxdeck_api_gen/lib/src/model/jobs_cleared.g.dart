// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jobs_cleared.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$JobsCleared extends JobsCleared {
  @override
  final int cleared;

  factory _$JobsCleared([void Function(JobsClearedBuilder)? updates]) =>
      (JobsClearedBuilder()..update(updates))._build();

  _$JobsCleared._({required this.cleared}) : super._();
  @override
  JobsCleared rebuild(void Function(JobsClearedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  JobsClearedBuilder toBuilder() => JobsClearedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is JobsCleared && cleared == other.cleared;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cleared.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'JobsCleared',
    )..add('cleared', cleared)).toString();
  }
}

class JobsClearedBuilder implements Builder<JobsCleared, JobsClearedBuilder> {
  _$JobsCleared? _$v;

  int? _cleared;
  int? get cleared => _$this._cleared;
  set cleared(int? cleared) => _$this._cleared = cleared;

  JobsClearedBuilder() {
    JobsCleared._defaults(this);
  }

  JobsClearedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cleared = $v.cleared;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(JobsCleared other) {
    _$v = other as _$JobsCleared;
  }

  @override
  void update(void Function(JobsClearedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  JobsCleared build() => _build();

  _$JobsCleared _build() {
    final _$result =
        _$v ??
        _$JobsCleared._(
          cleared: BuiltValueNullFieldError.checkNotNull(
            cleared,
            r'JobsCleared',
            'cleared',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
