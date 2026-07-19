// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'opml_import_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OpmlImportResult extends OpmlImportResult {
  @override
  final BuiltList<OpmlImportEntry> results;

  factory _$OpmlImportResult([
    void Function(OpmlImportResultBuilder)? updates,
  ]) => (OpmlImportResultBuilder()..update(updates))._build();

  _$OpmlImportResult._({required this.results}) : super._();
  @override
  OpmlImportResult rebuild(void Function(OpmlImportResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OpmlImportResultBuilder toBuilder() =>
      OpmlImportResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OpmlImportResult && results == other.results;
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
      r'OpmlImportResult',
    )..add('results', results)).toString();
  }
}

class OpmlImportResultBuilder
    implements Builder<OpmlImportResult, OpmlImportResultBuilder> {
  _$OpmlImportResult? _$v;

  ListBuilder<OpmlImportEntry>? _results;
  ListBuilder<OpmlImportEntry> get results =>
      _$this._results ??= ListBuilder<OpmlImportEntry>();
  set results(ListBuilder<OpmlImportEntry>? results) =>
      _$this._results = results;

  OpmlImportResultBuilder() {
    OpmlImportResult._defaults(this);
  }

  OpmlImportResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _results = $v.results.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OpmlImportResult other) {
    _$v = other as _$OpmlImportResult;
  }

  @override
  void update(void Function(OpmlImportResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OpmlImportResult build() => _build();

  _$OpmlImportResult _build() {
    _$OpmlImportResult _$result;
    try {
      _$result = _$v ?? _$OpmlImportResult._(results: results.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'results';
        results.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'OpmlImportResult',
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
