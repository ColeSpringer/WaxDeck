// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_series_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookSeriesEntry extends BookSeriesEntry {
  @override
  final String? sequence;
  @override
  final ItemSummary book;

  factory _$BookSeriesEntry([void Function(BookSeriesEntryBuilder)? updates]) =>
      (BookSeriesEntryBuilder()..update(updates))._build();

  _$BookSeriesEntry._({this.sequence, required this.book}) : super._();
  @override
  BookSeriesEntry rebuild(void Function(BookSeriesEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookSeriesEntryBuilder toBuilder() => BookSeriesEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookSeriesEntry &&
        sequence == other.sequence &&
        book == other.book;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, sequence.hashCode);
    _$hash = $jc(_$hash, book.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookSeriesEntry')
          ..add('sequence', sequence)
          ..add('book', book))
        .toString();
  }
}

class BookSeriesEntryBuilder
    implements Builder<BookSeriesEntry, BookSeriesEntryBuilder> {
  _$BookSeriesEntry? _$v;

  String? _sequence;
  String? get sequence => _$this._sequence;
  set sequence(String? sequence) => _$this._sequence = sequence;

  ItemSummary? _book;
  ItemSummary? get book => _$this._book;
  set book(ItemSummary? book) => _$this._book = book;

  BookSeriesEntryBuilder() {
    BookSeriesEntry._defaults(this);
  }

  BookSeriesEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _sequence = $v.sequence;
      _book = $v.book;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookSeriesEntry other) {
    _$v = other as _$BookSeriesEntry;
  }

  @override
  void update(void Function(BookSeriesEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookSeriesEntry build() => _build();

  _$BookSeriesEntry _build() {
    final _$result =
        _$v ??
        _$BookSeriesEntry._(
          sequence: sequence,
          book: BuiltValueNullFieldError.checkNotNull(
            book,
            r'BookSeriesEntry',
            'book',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
