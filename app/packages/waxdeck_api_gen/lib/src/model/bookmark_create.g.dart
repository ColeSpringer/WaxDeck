// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmark_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookmarkCreate extends BookmarkCreate {
  @override
  final int positionMs;
  @override
  final String? note;

  factory _$BookmarkCreate([void Function(BookmarkCreateBuilder)? updates]) =>
      (BookmarkCreateBuilder()..update(updates))._build();

  _$BookmarkCreate._({required this.positionMs, this.note}) : super._();
  @override
  BookmarkCreate rebuild(void Function(BookmarkCreateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookmarkCreateBuilder toBuilder() => BookmarkCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookmarkCreate &&
        positionMs == other.positionMs &&
        note == other.note;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookmarkCreate')
          ..add('positionMs', positionMs)
          ..add('note', note))
        .toString();
  }
}

class BookmarkCreateBuilder
    implements Builder<BookmarkCreate, BookmarkCreateBuilder> {
  _$BookmarkCreate? _$v;

  int? _positionMs;
  int? get positionMs => _$this._positionMs;
  set positionMs(int? positionMs) => _$this._positionMs = positionMs;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  BookmarkCreateBuilder() {
    BookmarkCreate._defaults(this);
  }

  BookmarkCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _positionMs = $v.positionMs;
      _note = $v.note;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookmarkCreate other) {
    _$v = other as _$BookmarkCreate;
  }

  @override
  void update(void Function(BookmarkCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookmarkCreate build() => _build();

  _$BookmarkCreate _build() {
    final _$result =
        _$v ??
        _$BookmarkCreate._(
          positionMs: BuiltValueNullFieldError.checkNotNull(
            positionMs,
            r'BookmarkCreate',
            'positionMs',
          ),
          note: note,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
