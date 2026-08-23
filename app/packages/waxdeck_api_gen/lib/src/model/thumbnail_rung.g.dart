// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thumbnail_rung.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ThumbnailRung extends ThumbnailRung {
  @override
  final int size;
  @override
  final int rows;
  @override
  final int bytes;

  factory _$ThumbnailRung([void Function(ThumbnailRungBuilder)? updates]) =>
      (ThumbnailRungBuilder()..update(updates))._build();

  _$ThumbnailRung._({
    required this.size,
    required this.rows,
    required this.bytes,
  }) : super._();
  @override
  ThumbnailRung rebuild(void Function(ThumbnailRungBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ThumbnailRungBuilder toBuilder() => ThumbnailRungBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ThumbnailRung &&
        size == other.size &&
        rows == other.rows &&
        bytes == other.bytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, size.hashCode);
    _$hash = $jc(_$hash, rows.hashCode);
    _$hash = $jc(_$hash, bytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ThumbnailRung')
          ..add('size', size)
          ..add('rows', rows)
          ..add('bytes', bytes))
        .toString();
  }
}

class ThumbnailRungBuilder
    implements Builder<ThumbnailRung, ThumbnailRungBuilder> {
  _$ThumbnailRung? _$v;

  int? _size;
  int? get size => _$this._size;
  set size(int? size) => _$this._size = size;

  int? _rows;
  int? get rows => _$this._rows;
  set rows(int? rows) => _$this._rows = rows;

  int? _bytes;
  int? get bytes => _$this._bytes;
  set bytes(int? bytes) => _$this._bytes = bytes;

  ThumbnailRungBuilder() {
    ThumbnailRung._defaults(this);
  }

  ThumbnailRungBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _size = $v.size;
      _rows = $v.rows;
      _bytes = $v.bytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ThumbnailRung other) {
    _$v = other as _$ThumbnailRung;
  }

  @override
  void update(void Function(ThumbnailRungBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ThumbnailRung build() => _build();

  _$ThumbnailRung _build() {
    final _$result =
        _$v ??
        _$ThumbnailRung._(
          size: BuiltValueNullFieldError.checkNotNull(
            size,
            r'ThumbnailRung',
            'size',
          ),
          rows: BuiltValueNullFieldError.checkNotNull(
            rows,
            r'ThumbnailRung',
            'rows',
          ),
          bytes: BuiltValueNullFieldError.checkNotNull(
            bytes,
            r'ThumbnailRung',
            'bytes',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
