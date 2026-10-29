// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'm3u_preview.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$M3uPreview extends M3uPreview {
  @override
  final int matched;
  @override
  final int merged;
  @override
  final int unmatched;
  @override
  final BuiltList<M3uPreviewEntry> entries;

  factory _$M3uPreview([void Function(M3uPreviewBuilder)? updates]) =>
      (M3uPreviewBuilder()..update(updates))._build();

  _$M3uPreview._({
    required this.matched,
    required this.merged,
    required this.unmatched,
    required this.entries,
  }) : super._();
  @override
  M3uPreview rebuild(void Function(M3uPreviewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  M3uPreviewBuilder toBuilder() => M3uPreviewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is M3uPreview &&
        matched == other.matched &&
        merged == other.merged &&
        unmatched == other.unmatched &&
        entries == other.entries;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, matched.hashCode);
    _$hash = $jc(_$hash, merged.hashCode);
    _$hash = $jc(_$hash, unmatched.hashCode);
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'M3uPreview')
          ..add('matched', matched)
          ..add('merged', merged)
          ..add('unmatched', unmatched)
          ..add('entries', entries))
        .toString();
  }
}

class M3uPreviewBuilder implements Builder<M3uPreview, M3uPreviewBuilder> {
  _$M3uPreview? _$v;

  int? _matched;
  int? get matched => _$this._matched;
  set matched(int? matched) => _$this._matched = matched;

  int? _merged;
  int? get merged => _$this._merged;
  set merged(int? merged) => _$this._merged = merged;

  int? _unmatched;
  int? get unmatched => _$this._unmatched;
  set unmatched(int? unmatched) => _$this._unmatched = unmatched;

  ListBuilder<M3uPreviewEntry>? _entries;
  ListBuilder<M3uPreviewEntry> get entries =>
      _$this._entries ??= ListBuilder<M3uPreviewEntry>();
  set entries(ListBuilder<M3uPreviewEntry>? entries) =>
      _$this._entries = entries;

  M3uPreviewBuilder() {
    M3uPreview._defaults(this);
  }

  M3uPreviewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _matched = $v.matched;
      _merged = $v.merged;
      _unmatched = $v.unmatched;
      _entries = $v.entries.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(M3uPreview other) {
    _$v = other as _$M3uPreview;
  }

  @override
  void update(void Function(M3uPreviewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  M3uPreview build() => _build();

  _$M3uPreview _build() {
    _$M3uPreview _$result;
    try {
      _$result =
          _$v ??
          _$M3uPreview._(
            matched: BuiltValueNullFieldError.checkNotNull(
              matched,
              r'M3uPreview',
              'matched',
            ),
            merged: BuiltValueNullFieldError.checkNotNull(
              merged,
              r'M3uPreview',
              'merged',
            ),
            unmatched: BuiltValueNullFieldError.checkNotNull(
              unmatched,
              r'M3uPreview',
              'unmatched',
            ),
            entries: entries.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'M3uPreview',
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
