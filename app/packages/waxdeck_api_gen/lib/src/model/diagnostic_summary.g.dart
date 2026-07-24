// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diagnostic_summary.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DiagnosticSummary extends DiagnosticSummary {
  @override
  final BuiltList<DiagnosticCount> counts;

  factory _$DiagnosticSummary([
    void Function(DiagnosticSummaryBuilder)? updates,
  ]) => (DiagnosticSummaryBuilder()..update(updates))._build();

  _$DiagnosticSummary._({required this.counts}) : super._();
  @override
  DiagnosticSummary rebuild(void Function(DiagnosticSummaryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DiagnosticSummaryBuilder toBuilder() =>
      DiagnosticSummaryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DiagnosticSummary && counts == other.counts;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, counts.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'DiagnosticSummary',
    )..add('counts', counts)).toString();
  }
}

class DiagnosticSummaryBuilder
    implements Builder<DiagnosticSummary, DiagnosticSummaryBuilder> {
  _$DiagnosticSummary? _$v;

  ListBuilder<DiagnosticCount>? _counts;
  ListBuilder<DiagnosticCount> get counts =>
      _$this._counts ??= ListBuilder<DiagnosticCount>();
  set counts(ListBuilder<DiagnosticCount>? counts) => _$this._counts = counts;

  DiagnosticSummaryBuilder() {
    DiagnosticSummary._defaults(this);
  }

  DiagnosticSummaryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _counts = $v.counts.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DiagnosticSummary other) {
    _$v = other as _$DiagnosticSummary;
  }

  @override
  void update(void Function(DiagnosticSummaryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DiagnosticSummary build() => _build();

  _$DiagnosticSummary _build() {
    _$DiagnosticSummary _$result;
    try {
      _$result = _$v ?? _$DiagnosticSummary._(counts: counts.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'counts';
        counts.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'DiagnosticSummary',
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
