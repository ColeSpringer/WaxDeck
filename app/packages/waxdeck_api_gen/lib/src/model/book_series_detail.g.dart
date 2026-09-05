// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_series_detail.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookSeriesDetail extends BookSeriesDetail {
  @override
  final String pid;
  @override
  final String name;
  @override
  final int? bookCount;
  @override
  final int? totalDurationMs;
  @override
  final BuiltList<BookSeriesEntry> books;

  factory _$BookSeriesDetail([
    void Function(BookSeriesDetailBuilder)? updates,
  ]) => (BookSeriesDetailBuilder()..update(updates))._build();

  _$BookSeriesDetail._({
    required this.pid,
    required this.name,
    this.bookCount,
    this.totalDurationMs,
    required this.books,
  }) : super._();
  @override
  BookSeriesDetail rebuild(void Function(BookSeriesDetailBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookSeriesDetailBuilder toBuilder() =>
      BookSeriesDetailBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookSeriesDetail &&
        pid == other.pid &&
        name == other.name &&
        bookCount == other.bookCount &&
        totalDurationMs == other.totalDurationMs &&
        books == other.books;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, bookCount.hashCode);
    _$hash = $jc(_$hash, totalDurationMs.hashCode);
    _$hash = $jc(_$hash, books.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookSeriesDetail')
          ..add('pid', pid)
          ..add('name', name)
          ..add('bookCount', bookCount)
          ..add('totalDurationMs', totalDurationMs)
          ..add('books', books))
        .toString();
  }
}

class BookSeriesDetailBuilder
    implements Builder<BookSeriesDetail, BookSeriesDetailBuilder> {
  _$BookSeriesDetail? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _bookCount;
  int? get bookCount => _$this._bookCount;
  set bookCount(int? bookCount) => _$this._bookCount = bookCount;

  int? _totalDurationMs;
  int? get totalDurationMs => _$this._totalDurationMs;
  set totalDurationMs(int? totalDurationMs) =>
      _$this._totalDurationMs = totalDurationMs;

  ListBuilder<BookSeriesEntry>? _books;
  ListBuilder<BookSeriesEntry> get books =>
      _$this._books ??= ListBuilder<BookSeriesEntry>();
  set books(ListBuilder<BookSeriesEntry>? books) => _$this._books = books;

  BookSeriesDetailBuilder() {
    BookSeriesDetail._defaults(this);
  }

  BookSeriesDetailBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _name = $v.name;
      _bookCount = $v.bookCount;
      _totalDurationMs = $v.totalDurationMs;
      _books = $v.books.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookSeriesDetail other) {
    _$v = other as _$BookSeriesDetail;
  }

  @override
  void update(void Function(BookSeriesDetailBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookSeriesDetail build() => _build();

  _$BookSeriesDetail _build() {
    _$BookSeriesDetail _$result;
    try {
      _$result =
          _$v ??
          _$BookSeriesDetail._(
            pid: BuiltValueNullFieldError.checkNotNull(
              pid,
              r'BookSeriesDetail',
              'pid',
            ),
            name: BuiltValueNullFieldError.checkNotNull(
              name,
              r'BookSeriesDetail',
              'name',
            ),
            bookCount: bookCount,
            totalDurationMs: totalDurationMs,
            books: books.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'books';
        books.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'BookSeriesDetail',
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
