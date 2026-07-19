// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radio_directory_results.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RadioDirectoryResults extends RadioDirectoryResults {
  @override
  final BuiltList<RadioDirectoryEntry> entries;

  factory _$RadioDirectoryResults([
    void Function(RadioDirectoryResultsBuilder)? updates,
  ]) => (RadioDirectoryResultsBuilder()..update(updates))._build();

  _$RadioDirectoryResults._({required this.entries}) : super._();
  @override
  RadioDirectoryResults rebuild(
    void Function(RadioDirectoryResultsBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  RadioDirectoryResultsBuilder toBuilder() =>
      RadioDirectoryResultsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RadioDirectoryResults && entries == other.entries;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'RadioDirectoryResults',
    )..add('entries', entries)).toString();
  }
}

class RadioDirectoryResultsBuilder
    implements Builder<RadioDirectoryResults, RadioDirectoryResultsBuilder> {
  _$RadioDirectoryResults? _$v;

  ListBuilder<RadioDirectoryEntry>? _entries;
  ListBuilder<RadioDirectoryEntry> get entries =>
      _$this._entries ??= ListBuilder<RadioDirectoryEntry>();
  set entries(ListBuilder<RadioDirectoryEntry>? entries) =>
      _$this._entries = entries;

  RadioDirectoryResultsBuilder() {
    RadioDirectoryResults._defaults(this);
  }

  RadioDirectoryResultsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entries = $v.entries.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RadioDirectoryResults other) {
    _$v = other as _$RadioDirectoryResults;
  }

  @override
  void update(void Function(RadioDirectoryResultsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RadioDirectoryResults build() => _build();

  _$RadioDirectoryResults _build() {
    _$RadioDirectoryResults _$result;
    try {
      _$result = _$v ?? _$RadioDirectoryResults._(entries: entries.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'RadioDirectoryResults',
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
