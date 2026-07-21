// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_bulk_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReviewBulkResult extends ReviewBulkResult {
  @override
  final BuiltList<ReviewBulkOutcome> results;

  factory _$ReviewBulkResult([
    void Function(ReviewBulkResultBuilder)? updates,
  ]) => (ReviewBulkResultBuilder()..update(updates))._build();

  _$ReviewBulkResult._({required this.results}) : super._();
  @override
  ReviewBulkResult rebuild(void Function(ReviewBulkResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReviewBulkResultBuilder toBuilder() =>
      ReviewBulkResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewBulkResult && results == other.results;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, results.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'ReviewBulkResult',
    )..add('results', results)).toString();
  }
}

class ReviewBulkResultBuilder
    implements Builder<ReviewBulkResult, ReviewBulkResultBuilder> {
  _$ReviewBulkResult? _$v;

  ListBuilder<ReviewBulkOutcome>? _results;
  ListBuilder<ReviewBulkOutcome> get results =>
      _$this._results ??= ListBuilder<ReviewBulkOutcome>();
  set results(ListBuilder<ReviewBulkOutcome>? results) =>
      _$this._results = results;

  ReviewBulkResultBuilder() {
    ReviewBulkResult._defaults(this);
  }

  ReviewBulkResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _results = $v.results.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewBulkResult other) {
    _$v = other as _$ReviewBulkResult;
  }

  @override
  void update(void Function(ReviewBulkResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewBulkResult build() => _build();

  _$ReviewBulkResult _build() {
    _$ReviewBulkResult _$result;
    try {
      _$result = _$v ?? _$ReviewBulkResult._(results: results.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'results';
        results.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ReviewBulkResult',
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
