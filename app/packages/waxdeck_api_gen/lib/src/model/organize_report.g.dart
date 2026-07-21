// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_report.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OrganizeReport extends OrganizeReport {
  @override
  final int moved;
  @override
  final int skipped;
  @override
  final int failed;
  @override
  final BuiltList<OrganizeFailure>? failures;

  factory _$OrganizeReport([void Function(OrganizeReportBuilder)? updates]) =>
      (OrganizeReportBuilder()..update(updates))._build();

  _$OrganizeReport._({
    required this.moved,
    required this.skipped,
    required this.failed,
    this.failures,
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
        moved == other.moved &&
        skipped == other.skipped &&
        failed == other.failed &&
        failures == other.failures;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, moved.hashCode);
    _$hash = $jc(_$hash, skipped.hashCode);
    _$hash = $jc(_$hash, failed.hashCode);
    _$hash = $jc(_$hash, failures.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizeReport')
          ..add('moved', moved)
          ..add('skipped', skipped)
          ..add('failed', failed)
          ..add('failures', failures))
        .toString();
  }
}

class OrganizeReportBuilder
    implements Builder<OrganizeReport, OrganizeReportBuilder> {
  _$OrganizeReport? _$v;

  int? _moved;
  int? get moved => _$this._moved;
  set moved(int? moved) => _$this._moved = moved;

  int? _skipped;
  int? get skipped => _$this._skipped;
  set skipped(int? skipped) => _$this._skipped = skipped;

  int? _failed;
  int? get failed => _$this._failed;
  set failed(int? failed) => _$this._failed = failed;

  ListBuilder<OrganizeFailure>? _failures;
  ListBuilder<OrganizeFailure> get failures =>
      _$this._failures ??= ListBuilder<OrganizeFailure>();
  set failures(ListBuilder<OrganizeFailure>? failures) =>
      _$this._failures = failures;

  OrganizeReportBuilder() {
    OrganizeReport._defaults(this);
  }

  OrganizeReportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _moved = $v.moved;
      _skipped = $v.skipped;
      _failed = $v.failed;
      _failures = $v.failures?.toBuilder();
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
            failed: BuiltValueNullFieldError.checkNotNull(
              failed,
              r'OrganizeReport',
              'failed',
            ),
            failures: _failures?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
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
