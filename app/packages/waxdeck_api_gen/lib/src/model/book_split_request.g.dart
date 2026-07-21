// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_split_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookSplitRequest extends BookSplitRequest {
  @override
  final bool? keepOriginals;

  factory _$BookSplitRequest([
    void Function(BookSplitRequestBuilder)? updates,
  ]) => (BookSplitRequestBuilder()..update(updates))._build();

  _$BookSplitRequest._({this.keepOriginals}) : super._();
  @override
  BookSplitRequest rebuild(void Function(BookSplitRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookSplitRequestBuilder toBuilder() =>
      BookSplitRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookSplitRequest && keepOriginals == other.keepOriginals;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, keepOriginals.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'BookSplitRequest',
    )..add('keepOriginals', keepOriginals)).toString();
  }
}

class BookSplitRequestBuilder
    implements Builder<BookSplitRequest, BookSplitRequestBuilder> {
  _$BookSplitRequest? _$v;

  bool? _keepOriginals;
  bool? get keepOriginals => _$this._keepOriginals;
  set keepOriginals(bool? keepOriginals) =>
      _$this._keepOriginals = keepOriginals;

  BookSplitRequestBuilder() {
    BookSplitRequest._defaults(this);
  }

  BookSplitRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _keepOriginals = $v.keepOriginals;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookSplitRequest other) {
    _$v = other as _$BookSplitRequest;
  }

  @override
  void update(void Function(BookSplitRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookSplitRequest build() => _build();

  _$BookSplitRequest _build() {
    final _$result = _$v ?? _$BookSplitRequest._(keepOriginals: keepOriginals);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
