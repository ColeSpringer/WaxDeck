// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmark_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookmarkList extends BookmarkList {
  @override
  final BuiltList<Bookmark> bookmarks;

  factory _$BookmarkList([void Function(BookmarkListBuilder)? updates]) =>
      (BookmarkListBuilder()..update(updates))._build();

  _$BookmarkList._({required this.bookmarks}) : super._();
  @override
  BookmarkList rebuild(void Function(BookmarkListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookmarkListBuilder toBuilder() => BookmarkListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookmarkList && bookmarks == other.bookmarks;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookmarks.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'BookmarkList',
    )..add('bookmarks', bookmarks)).toString();
  }
}

class BookmarkListBuilder
    implements Builder<BookmarkList, BookmarkListBuilder> {
  _$BookmarkList? _$v;

  ListBuilder<Bookmark>? _bookmarks;
  ListBuilder<Bookmark> get bookmarks =>
      _$this._bookmarks ??= ListBuilder<Bookmark>();
  set bookmarks(ListBuilder<Bookmark>? bookmarks) =>
      _$this._bookmarks = bookmarks;

  BookmarkListBuilder() {
    BookmarkList._defaults(this);
  }

  BookmarkListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookmarks = $v.bookmarks.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookmarkList other) {
    _$v = other as _$BookmarkList;
  }

  @override
  void update(void Function(BookmarkListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookmarkList build() => _build();

  _$BookmarkList _build() {
    _$BookmarkList _$result;
    try {
      _$result = _$v ?? _$BookmarkList._(bookmarks: bookmarks.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'bookmarks';
        bookmarks.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'BookmarkList',
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
