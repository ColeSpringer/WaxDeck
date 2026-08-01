// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmark.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Bookmark extends Bookmark {
  @override
  final String id;
  @override
  final int positionMs;
  @override
  final String? note;
  @override
  final DateTime createdAt;

  factory _$Bookmark([void Function(BookmarkBuilder)? updates]) =>
      (BookmarkBuilder()..update(updates))._build();

  _$Bookmark._({
    required this.id,
    required this.positionMs,
    this.note,
    required this.createdAt,
  }) : super._();
  @override
  Bookmark rebuild(void Function(BookmarkBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookmarkBuilder toBuilder() => BookmarkBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Bookmark &&
        id == other.id &&
        positionMs == other.positionMs &&
        note == other.note &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Bookmark')
          ..add('id', id)
          ..add('positionMs', positionMs)
          ..add('note', note)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class BookmarkBuilder implements Builder<Bookmark, BookmarkBuilder> {
  _$Bookmark? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  int? _positionMs;
  int? get positionMs => _$this._positionMs;
  set positionMs(int? positionMs) => _$this._positionMs = positionMs;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  BookmarkBuilder() {
    Bookmark._defaults(this);
  }

  BookmarkBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _positionMs = $v.positionMs;
      _note = $v.note;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Bookmark other) {
    _$v = other as _$Bookmark;
  }

  @override
  void update(void Function(BookmarkBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Bookmark build() => _build();

  _$Bookmark _build() {
    final _$result =
        _$v ??
        _$Bookmark._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'Bookmark', 'id'),
          positionMs: BuiltValueNullFieldError.checkNotNull(
            positionMs,
            r'Bookmark',
            'positionMs',
          ),
          note: note,
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'Bookmark',
            'createdAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
