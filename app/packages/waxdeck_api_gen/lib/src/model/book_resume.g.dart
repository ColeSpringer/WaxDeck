// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_resume.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookResume extends BookResume {
  @override
  final int positionMs;
  @override
  final ChapterMark? chapter;
  @override
  final DateTime? updatedAt;

  factory _$BookResume([void Function(BookResumeBuilder)? updates]) =>
      (BookResumeBuilder()..update(updates))._build();

  _$BookResume._({required this.positionMs, this.chapter, this.updatedAt})
    : super._();
  @override
  BookResume rebuild(void Function(BookResumeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookResumeBuilder toBuilder() => BookResumeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookResume &&
        positionMs == other.positionMs &&
        chapter == other.chapter &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jc(_$hash, chapter.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookResume')
          ..add('positionMs', positionMs)
          ..add('chapter', chapter)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class BookResumeBuilder implements Builder<BookResume, BookResumeBuilder> {
  _$BookResume? _$v;

  int? _positionMs;
  int? get positionMs => _$this._positionMs;
  set positionMs(int? positionMs) => _$this._positionMs = positionMs;

  ChapterMarkBuilder? _chapter;
  ChapterMarkBuilder get chapter => _$this._chapter ??= ChapterMarkBuilder();
  set chapter(ChapterMarkBuilder? chapter) => _$this._chapter = chapter;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  BookResumeBuilder() {
    BookResume._defaults(this);
  }

  BookResumeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _positionMs = $v.positionMs;
      _chapter = $v.chapter?.toBuilder();
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookResume other) {
    _$v = other as _$BookResume;
  }

  @override
  void update(void Function(BookResumeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookResume build() => _build();

  _$BookResume _build() {
    _$BookResume _$result;
    try {
      _$result =
          _$v ??
          _$BookResume._(
            positionMs: BuiltValueNullFieldError.checkNotNull(
              positionMs,
              r'BookResume',
              'positionMs',
            ),
            chapter: _chapter?.build(),
            updatedAt: updatedAt,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'chapter';
        _chapter?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'BookResume',
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
