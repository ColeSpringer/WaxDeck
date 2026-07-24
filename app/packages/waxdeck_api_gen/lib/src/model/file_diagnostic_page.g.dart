// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_diagnostic_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$FileDiagnosticPage extends FileDiagnosticPage {
  @override
  final BuiltList<FileDiagnostic> diagnostics;
  @override
  final String? nextCursor;

  factory _$FileDiagnosticPage([
    void Function(FileDiagnosticPageBuilder)? updates,
  ]) => (FileDiagnosticPageBuilder()..update(updates))._build();

  _$FileDiagnosticPage._({required this.diagnostics, this.nextCursor})
    : super._();
  @override
  FileDiagnosticPage rebuild(
    void Function(FileDiagnosticPageBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  FileDiagnosticPageBuilder toBuilder() =>
      FileDiagnosticPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FileDiagnosticPage &&
        diagnostics == other.diagnostics &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, diagnostics.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FileDiagnosticPage')
          ..add('diagnostics', diagnostics)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class FileDiagnosticPageBuilder
    implements Builder<FileDiagnosticPage, FileDiagnosticPageBuilder> {
  _$FileDiagnosticPage? _$v;

  ListBuilder<FileDiagnostic>? _diagnostics;
  ListBuilder<FileDiagnostic> get diagnostics =>
      _$this._diagnostics ??= ListBuilder<FileDiagnostic>();
  set diagnostics(ListBuilder<FileDiagnostic>? diagnostics) =>
      _$this._diagnostics = diagnostics;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  FileDiagnosticPageBuilder() {
    FileDiagnosticPage._defaults(this);
  }

  FileDiagnosticPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _diagnostics = $v.diagnostics.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FileDiagnosticPage other) {
    _$v = other as _$FileDiagnosticPage;
  }

  @override
  void update(void Function(FileDiagnosticPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FileDiagnosticPage build() => _build();

  _$FileDiagnosticPage _build() {
    _$FileDiagnosticPage _$result;
    try {
      _$result =
          _$v ??
          _$FileDiagnosticPage._(
            diagnostics: diagnostics.build(),
            nextCursor: nextCursor,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'diagnostics';
        diagnostics.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'FileDiagnosticPage',
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
