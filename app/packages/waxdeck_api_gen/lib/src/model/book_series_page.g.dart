// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_series_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookSeriesPage extends BookSeriesPage {
  @override
  final BuiltList<BookSeries> series;
  @override
  final String? nextCursor;

  factory _$BookSeriesPage([void Function(BookSeriesPageBuilder)? updates]) =>
      (BookSeriesPageBuilder()..update(updates))._build();

  _$BookSeriesPage._({required this.series, this.nextCursor}) : super._();
  @override
  BookSeriesPage rebuild(void Function(BookSeriesPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookSeriesPageBuilder toBuilder() => BookSeriesPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookSeriesPage &&
        series == other.series &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, series.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookSeriesPage')
          ..add('series', series)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class BookSeriesPageBuilder
    implements Builder<BookSeriesPage, BookSeriesPageBuilder> {
  _$BookSeriesPage? _$v;

  ListBuilder<BookSeries>? _series;
  ListBuilder<BookSeries> get series =>
      _$this._series ??= ListBuilder<BookSeries>();
  set series(ListBuilder<BookSeries>? series) => _$this._series = series;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  BookSeriesPageBuilder() {
    BookSeriesPage._defaults(this);
  }

  BookSeriesPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _series = $v.series.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookSeriesPage other) {
    _$v = other as _$BookSeriesPage;
  }

  @override
  void update(void Function(BookSeriesPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookSeriesPage build() => _build();

  _$BookSeriesPage _build() {
    _$BookSeriesPage _$result;
    try {
      _$result =
          _$v ??
          _$BookSeriesPage._(series: series.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'series';
        series.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'BookSeriesPage',
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
