// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_entry_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReviewEntryPage extends ReviewEntryPage {
  @override
  final BuiltList<ReviewEntry> entries;
  @override
  final String? nextCursor;

  factory _$ReviewEntryPage([void Function(ReviewEntryPageBuilder)? updates]) =>
      (ReviewEntryPageBuilder()..update(updates))._build();

  _$ReviewEntryPage._({required this.entries, this.nextCursor}) : super._();
  @override
  ReviewEntryPage rebuild(void Function(ReviewEntryPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReviewEntryPageBuilder toBuilder() => ReviewEntryPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewEntryPage &&
        entries == other.entries &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewEntryPage')
          ..add('entries', entries)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class ReviewEntryPageBuilder
    implements Builder<ReviewEntryPage, ReviewEntryPageBuilder> {
  _$ReviewEntryPage? _$v;

  ListBuilder<ReviewEntry>? _entries;
  ListBuilder<ReviewEntry> get entries =>
      _$this._entries ??= ListBuilder<ReviewEntry>();
  set entries(ListBuilder<ReviewEntry>? entries) => _$this._entries = entries;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  ReviewEntryPageBuilder() {
    ReviewEntryPage._defaults(this);
  }

  ReviewEntryPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entries = $v.entries.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewEntryPage other) {
    _$v = other as _$ReviewEntryPage;
  }

  @override
  void update(void Function(ReviewEntryPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewEntryPage build() => _build();

  _$ReviewEntryPage _build() {
    _$ReviewEntryPage _$result;
    try {
      _$result =
          _$v ??
          _$ReviewEntryPage._(entries: entries.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ReviewEntryPage',
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
