// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_run_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentRunResult extends EnrichmentRunResult {
  @override
  final String jobPid;

  factory _$EnrichmentRunResult([
    void Function(EnrichmentRunResultBuilder)? updates,
  ]) => (EnrichmentRunResultBuilder()..update(updates))._build();

  _$EnrichmentRunResult._({required this.jobPid}) : super._();
  @override
  EnrichmentRunResult rebuild(
    void Function(EnrichmentRunResultBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EnrichmentRunResultBuilder toBuilder() =>
      EnrichmentRunResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentRunResult && jobPid == other.jobPid;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, jobPid.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'EnrichmentRunResult',
    )..add('jobPid', jobPid)).toString();
  }
}

class EnrichmentRunResultBuilder
    implements Builder<EnrichmentRunResult, EnrichmentRunResultBuilder> {
  _$EnrichmentRunResult? _$v;

  String? _jobPid;
  String? get jobPid => _$this._jobPid;
  set jobPid(String? jobPid) => _$this._jobPid = jobPid;

  EnrichmentRunResultBuilder() {
    EnrichmentRunResult._defaults(this);
  }

  EnrichmentRunResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _jobPid = $v.jobPid;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentRunResult other) {
    _$v = other as _$EnrichmentRunResult;
  }

  @override
  void update(void Function(EnrichmentRunResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentRunResult build() => _build();

  _$EnrichmentRunResult _build() {
    final _$result =
        _$v ??
        _$EnrichmentRunResult._(
          jobPid: BuiltValueNullFieldError.checkNotNull(
            jobPid,
            r'EnrichmentRunResult',
            'jobPid',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
