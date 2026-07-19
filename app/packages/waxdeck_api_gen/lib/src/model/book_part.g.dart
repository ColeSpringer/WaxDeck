// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_part.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookPart extends BookPart {
  @override
  final int index;
  @override
  final int startMs;
  @override
  final int durationMs;
  @override
  final String? displayName;

  factory _$BookPart([void Function(BookPartBuilder)? updates]) =>
      (BookPartBuilder()..update(updates))._build();

  _$BookPart._({
    required this.index,
    required this.startMs,
    required this.durationMs,
    this.displayName,
  }) : super._();
  @override
  BookPart rebuild(void Function(BookPartBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookPartBuilder toBuilder() => BookPartBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookPart &&
        index == other.index &&
        startMs == other.startMs &&
        durationMs == other.durationMs &&
        displayName == other.displayName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, index.hashCode);
    _$hash = $jc(_$hash, startMs.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookPart')
          ..add('index', index)
          ..add('startMs', startMs)
          ..add('durationMs', durationMs)
          ..add('displayName', displayName))
        .toString();
  }
}

class BookPartBuilder implements Builder<BookPart, BookPartBuilder> {
  _$BookPart? _$v;

  int? _index;
  int? get index => _$this._index;
  set index(int? index) => _$this._index = index;

  int? _startMs;
  int? get startMs => _$this._startMs;
  set startMs(int? startMs) => _$this._startMs = startMs;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  BookPartBuilder() {
    BookPart._defaults(this);
  }

  BookPartBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _index = $v.index;
      _startMs = $v.startMs;
      _durationMs = $v.durationMs;
      _displayName = $v.displayName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookPart other) {
    _$v = other as _$BookPart;
  }

  @override
  void update(void Function(BookPartBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookPart build() => _build();

  _$BookPart _build() {
    final _$result =
        _$v ??
        _$BookPart._(
          index: BuiltValueNullFieldError.checkNotNull(
            index,
            r'BookPart',
            'index',
          ),
          startMs: BuiltValueNullFieldError.checkNotNull(
            startMs,
            r'BookPart',
            'startMs',
          ),
          durationMs: BuiltValueNullFieldError.checkNotNull(
            durationMs,
            r'BookPart',
            'durationMs',
          ),
          displayName: displayName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
