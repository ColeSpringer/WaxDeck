// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_series.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookSeries extends BookSeries {
  @override
  final String pid;
  @override
  final String name;
  @override
  final int? bookCount;
  @override
  final int? totalDurationMs;

  factory _$BookSeries([void Function(BookSeriesBuilder)? updates]) =>
      (BookSeriesBuilder()..update(updates))._build();

  _$BookSeries._({
    required this.pid,
    required this.name,
    this.bookCount,
    this.totalDurationMs,
  }) : super._();
  @override
  BookSeries rebuild(void Function(BookSeriesBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookSeriesBuilder toBuilder() => BookSeriesBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookSeries &&
        pid == other.pid &&
        name == other.name &&
        bookCount == other.bookCount &&
        totalDurationMs == other.totalDurationMs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, bookCount.hashCode);
    _$hash = $jc(_$hash, totalDurationMs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookSeries')
          ..add('pid', pid)
          ..add('name', name)
          ..add('bookCount', bookCount)
          ..add('totalDurationMs', totalDurationMs))
        .toString();
  }
}

class BookSeriesBuilder implements Builder<BookSeries, BookSeriesBuilder> {
  _$BookSeries? _$v;

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

  BookSeriesBuilder() {
    BookSeries._defaults(this);
  }

  BookSeriesBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _name = $v.name;
      _bookCount = $v.bookCount;
      _totalDurationMs = $v.totalDurationMs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookSeries other) {
    _$v = other as _$BookSeries;
  }

  @override
  void update(void Function(BookSeriesBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookSeries build() => _build();

  _$BookSeries _build() {
    final _$result =
        _$v ??
        _$BookSeries._(
          pid: BuiltValueNullFieldError.checkNotNull(pid, r'BookSeries', 'pid'),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'BookSeries',
            'name',
          ),
          bookCount: bookCount,
          totalDurationMs: totalDurationMs,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
