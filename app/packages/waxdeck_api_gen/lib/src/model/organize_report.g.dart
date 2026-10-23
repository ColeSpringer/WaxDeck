// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_report.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OrganizeReport extends OrganizeReport {
  @override
  final String jobPid;
  @override
  final int moved;
  @override
  final int skipped;
  @override
  final int held;
  @override
  final BuiltList<OrganizeHold>? holds;
  @override
  final int readOnlyLibraries;
  @override
  final int failed;
  @override
  final BuiltList<OrganizeFailure>? failures;
  @override
  final int? dirsPruned;

  factory _$OrganizeReport([void Function(OrganizeReportBuilder)? updates]) =>
      (OrganizeReportBuilder()..update(updates))._build();

  _$OrganizeReport._({
    required this.jobPid,
    required this.moved,
    required this.skipped,
    required this.held,
    this.holds,
    required this.readOnlyLibraries,
    required this.failed,
    this.failures,
    this.dirsPruned,
  }) : super._();
  @override
  OrganizeReport rebuild(void Function(OrganizeReportBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OrganizeReportBuilder toBuilder() => OrganizeReportBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizeReport &&
        jobPid == other.jobPid &&
        moved == other.moved &&
        skipped == other.skipped &&
        held == other.held &&
        holds == other.holds &&
        readOnlyLibraries == other.readOnlyLibraries &&
        failed == other.failed &&
        failures == other.failures &&
        dirsPruned == other.dirsPruned;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, jobPid.hashCode);
    _$hash = $jc(_$hash, moved.hashCode);
    _$hash = $jc(_$hash, skipped.hashCode);
    _$hash = $jc(_$hash, held.hashCode);
    _$hash = $jc(_$hash, holds.hashCode);
    _$hash = $jc(_$hash, readOnlyLibraries.hashCode);
    _$hash = $jc(_$hash, failed.hashCode);
    _$hash = $jc(_$hash, failures.hashCode);
    _$hash = $jc(_$hash, dirsPruned.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizeReport')
          ..add('jobPid', jobPid)
          ..add('moved', moved)
          ..add('skipped', skipped)
          ..add('held', held)
          ..add('holds', holds)
          ..add('readOnlyLibraries', readOnlyLibraries)
          ..add('failed', failed)
          ..add('failures', failures)
          ..add('dirsPruned', dirsPruned))
        .toString();
  }
}

class OrganizeReportBuilder
    implements Builder<OrganizeReport, OrganizeReportBuilder> {
  _$OrganizeReport? _$v;

  String? _jobPid;
  String? get jobPid => _$this._jobPid;
  set jobPid(String? jobPid) => _$this._jobPid = jobPid;

  int? _moved;
  int? get moved => _$this._moved;
  set moved(int? moved) => _$this._moved = moved;

  int? _skipped;
  int? get skipped => _$this._skipped;
  set skipped(int? skipped) => _$this._skipped = skipped;

  int? _held;
  int? get held => _$this._held;
  set held(int? held) => _$this._held = held;

  ListBuilder<OrganizeHold>? _holds;
  ListBuilder<OrganizeHold> get holds =>
      _$this._holds ??= ListBuilder<OrganizeHold>();
  set holds(ListBuilder<OrganizeHold>? holds) => _$this._holds = holds;

  int? _readOnlyLibraries;
  int? get readOnlyLibraries => _$this._readOnlyLibraries;
  set readOnlyLibraries(int? readOnlyLibraries) =>
      _$this._readOnlyLibraries = readOnlyLibraries;

  int? _failed;
  int? get failed => _$this._failed;
  set failed(int? failed) => _$this._failed = failed;

  ListBuilder<OrganizeFailure>? _failures;
  ListBuilder<OrganizeFailure> get failures =>
      _$this._failures ??= ListBuilder<OrganizeFailure>();
  set failures(ListBuilder<OrganizeFailure>? failures) =>
      _$this._failures = failures;

  int? _dirsPruned;
  int? get dirsPruned => _$this._dirsPruned;
  set dirsPruned(int? dirsPruned) => _$this._dirsPruned = dirsPruned;

  OrganizeReportBuilder() {
    OrganizeReport._defaults(this);
  }

  OrganizeReportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _jobPid = $v.jobPid;
      _moved = $v.moved;
      _skipped = $v.skipped;
      _held = $v.held;
      _holds = $v.holds?.toBuilder();
      _readOnlyLibraries = $v.readOnlyLibraries;
      _failed = $v.failed;
      _failures = $v.failures?.toBuilder();
      _dirsPruned = $v.dirsPruned;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizeReport other) {
    _$v = other as _$OrganizeReport;
  }

  @override
  void update(void Function(OrganizeReportBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizeReport build() => _build();

  _$OrganizeReport _build() {
    _$OrganizeReport _$result;
    try {
      _$result =
          _$v ??
          _$OrganizeReport._(
            jobPid: BuiltValueNullFieldError.checkNotNull(
              jobPid,
              r'OrganizeReport',
              'jobPid',
            ),
            moved: BuiltValueNullFieldError.checkNotNull(
              moved,
              r'OrganizeReport',
              'moved',
            ),
            skipped: BuiltValueNullFieldError.checkNotNull(
              skipped,
              r'OrganizeReport',
              'skipped',
            ),
            held: BuiltValueNullFieldError.checkNotNull(
              held,
              r'OrganizeReport',
              'held',
            ),
            holds: _holds?.build(),
            readOnlyLibraries: BuiltValueNullFieldError.checkNotNull(
              readOnlyLibraries,
              r'OrganizeReport',
              'readOnlyLibraries',
            ),
            failed: BuiltValueNullFieldError.checkNotNull(
              failed,
              r'OrganizeReport',
              'failed',
            ),
            failures: _failures?.build(),
            dirsPruned: dirsPruned,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'holds';
        _holds?.build();

        _$failedField = 'failures';
        _failures?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'OrganizeReport',
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
