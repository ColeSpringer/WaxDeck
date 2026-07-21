// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_merge_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookMergeRequest extends BookMergeRequest {
  @override
  final BuiltList<String>? titles;
  @override
  final bool? keepOriginals;

  factory _$BookMergeRequest([
    void Function(BookMergeRequestBuilder)? updates,
  ]) => (BookMergeRequestBuilder()..update(updates))._build();

  _$BookMergeRequest._({this.titles, this.keepOriginals}) : super._();
  @override
  BookMergeRequest rebuild(void Function(BookMergeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookMergeRequestBuilder toBuilder() =>
      BookMergeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookMergeRequest &&
        titles == other.titles &&
        keepOriginals == other.keepOriginals;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, titles.hashCode);
    _$hash = $jc(_$hash, keepOriginals.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookMergeRequest')
          ..add('titles', titles)
          ..add('keepOriginals', keepOriginals))
        .toString();
  }
}

class BookMergeRequestBuilder
    implements Builder<BookMergeRequest, BookMergeRequestBuilder> {
  _$BookMergeRequest? _$v;

  ListBuilder<String>? _titles;
  ListBuilder<String> get titles => _$this._titles ??= ListBuilder<String>();
  set titles(ListBuilder<String>? titles) => _$this._titles = titles;

  bool? _keepOriginals;
  bool? get keepOriginals => _$this._keepOriginals;
  set keepOriginals(bool? keepOriginals) =>
      _$this._keepOriginals = keepOriginals;

  BookMergeRequestBuilder() {
    BookMergeRequest._defaults(this);
  }

  BookMergeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _titles = $v.titles?.toBuilder();
      _keepOriginals = $v.keepOriginals;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookMergeRequest other) {
    _$v = other as _$BookMergeRequest;
  }

  @override
  void update(void Function(BookMergeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookMergeRequest build() => _build();

  _$BookMergeRequest _build() {
    _$BookMergeRequest _$result;
    try {
      _$result =
          _$v ??
          _$BookMergeRequest._(
            titles: _titles?.build(),
            keepOriginals: keepOriginals,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'titles';
        _titles?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'BookMergeRequest',
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
