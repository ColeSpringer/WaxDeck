// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chapters_edit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ChaptersEdit extends ChaptersEdit {
  @override
  final BuiltList<ChapterMark> chapters;
  @override
  final bool? lock;
  @override
  final bool? force;

  factory _$ChaptersEdit([void Function(ChaptersEditBuilder)? updates]) =>
      (ChaptersEditBuilder()..update(updates))._build();

  _$ChaptersEdit._({required this.chapters, this.lock, this.force}) : super._();
  @override
  ChaptersEdit rebuild(void Function(ChaptersEditBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ChaptersEditBuilder toBuilder() => ChaptersEditBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ChaptersEdit &&
        chapters == other.chapters &&
        lock == other.lock &&
        force == other.force;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, chapters.hashCode);
    _$hash = $jc(_$hash, lock.hashCode);
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ChaptersEdit')
          ..add('chapters', chapters)
          ..add('lock', lock)
          ..add('force', force))
        .toString();
  }
}

class ChaptersEditBuilder
    implements Builder<ChaptersEdit, ChaptersEditBuilder> {
  _$ChaptersEdit? _$v;

  ListBuilder<ChapterMark>? _chapters;
  ListBuilder<ChapterMark> get chapters =>
      _$this._chapters ??= ListBuilder<ChapterMark>();
  set chapters(ListBuilder<ChapterMark>? chapters) =>
      _$this._chapters = chapters;

  bool? _lock;
  bool? get lock => _$this._lock;
  set lock(bool? lock) => _$this._lock = lock;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  ChaptersEditBuilder() {
    ChaptersEdit._defaults(this);
  }

  ChaptersEditBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _chapters = $v.chapters.toBuilder();
      _lock = $v.lock;
      _force = $v.force;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ChaptersEdit other) {
    _$v = other as _$ChaptersEdit;
  }

  @override
  void update(void Function(ChaptersEditBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ChaptersEdit build() => _build();

  _$ChaptersEdit _build() {
    _$ChaptersEdit _$result;
    try {
      _$result =
          _$v ??
          _$ChaptersEdit._(
            chapters: chapters.build(),
            lock: lock,
            force: force,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'chapters';
        chapters.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ChaptersEdit',
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
