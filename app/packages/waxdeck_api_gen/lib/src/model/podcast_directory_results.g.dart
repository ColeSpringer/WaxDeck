// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'podcast_directory_results.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PodcastDirectoryResults extends PodcastDirectoryResults {
  @override
  final BuiltList<PodcastDirectoryEntry> entries;

  factory _$PodcastDirectoryResults([
    void Function(PodcastDirectoryResultsBuilder)? updates,
  ]) => (PodcastDirectoryResultsBuilder()..update(updates))._build();

  _$PodcastDirectoryResults._({required this.entries}) : super._();
  @override
  PodcastDirectoryResults rebuild(
    void Function(PodcastDirectoryResultsBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PodcastDirectoryResultsBuilder toBuilder() =>
      PodcastDirectoryResultsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PodcastDirectoryResults && entries == other.entries;
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
      r'PodcastDirectoryResults',
    )..add('entries', entries)).toString();
  }
}

class PodcastDirectoryResultsBuilder
    implements
        Builder<PodcastDirectoryResults, PodcastDirectoryResultsBuilder> {
  _$PodcastDirectoryResults? _$v;

  ListBuilder<PodcastDirectoryEntry>? _entries;
  ListBuilder<PodcastDirectoryEntry> get entries =>
      _$this._entries ??= ListBuilder<PodcastDirectoryEntry>();
  set entries(ListBuilder<PodcastDirectoryEntry>? entries) =>
      _$this._entries = entries;

  PodcastDirectoryResultsBuilder() {
    PodcastDirectoryResults._defaults(this);
  }

  PodcastDirectoryResultsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entries = $v.entries.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PodcastDirectoryResults other) {
    _$v = other as _$PodcastDirectoryResults;
  }

  @override
  void update(void Function(PodcastDirectoryResultsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PodcastDirectoryResults build() => _build();

  _$PodcastDirectoryResults _build() {
    _$PodcastDirectoryResults _$result;
    try {
      _$result = _$v ?? _$PodcastDirectoryResults._(entries: entries.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PodcastDirectoryResults',
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
