// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chapter_mark.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ChapterMark extends ChapterMark {
  @override
  final int index;
  @override
  final String? title;
  @override
  final int startMs;
  @override
  final int? endMs;

  factory _$ChapterMark([void Function(ChapterMarkBuilder)? updates]) =>
      (ChapterMarkBuilder()..update(updates))._build();

  _$ChapterMark._({
    required this.index,
    this.title,
    required this.startMs,
    this.endMs,
  }) : super._();
  @override
  ChapterMark rebuild(void Function(ChapterMarkBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ChapterMarkBuilder toBuilder() => ChapterMarkBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ChapterMark &&
        index == other.index &&
        title == other.title &&
        startMs == other.startMs &&
        endMs == other.endMs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, index.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, startMs.hashCode);
    _$hash = $jc(_$hash, endMs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ChapterMark')
          ..add('index', index)
          ..add('title', title)
          ..add('startMs', startMs)
          ..add('endMs', endMs))
        .toString();
  }
}

class ChapterMarkBuilder implements Builder<ChapterMark, ChapterMarkBuilder> {
  _$ChapterMark? _$v;

  int? _index;
  int? get index => _$this._index;
  set index(int? index) => _$this._index = index;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  int? _startMs;
  int? get startMs => _$this._startMs;
  set startMs(int? startMs) => _$this._startMs = startMs;

  int? _endMs;
  int? get endMs => _$this._endMs;
  set endMs(int? endMs) => _$this._endMs = endMs;

  ChapterMarkBuilder() {
    ChapterMark._defaults(this);
  }

  ChapterMarkBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _index = $v.index;
      _title = $v.title;
      _startMs = $v.startMs;
      _endMs = $v.endMs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ChapterMark other) {
    _$v = other as _$ChapterMark;
  }

  @override
  void update(void Function(ChapterMarkBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ChapterMark build() => _build();

  _$ChapterMark _build() {
    final _$result =
        _$v ??
        _$ChapterMark._(
          index: BuiltValueNullFieldError.checkNotNull(
            index,
            r'ChapterMark',
            'index',
          ),
          title: title,
          startMs: BuiltValueNullFieldError.checkNotNull(
            startMs,
            r'ChapterMark',
            'startMs',
          ),
          endMs: endMs,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
