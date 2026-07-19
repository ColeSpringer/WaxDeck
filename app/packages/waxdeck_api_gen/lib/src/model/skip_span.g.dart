// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skip_span.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SkipSpan extends SkipSpan {
  @override
  final int startMs;
  @override
  final int endMs;

  factory _$SkipSpan([void Function(SkipSpanBuilder)? updates]) =>
      (SkipSpanBuilder()..update(updates))._build();

  _$SkipSpan._({required this.startMs, required this.endMs}) : super._();
  @override
  SkipSpan rebuild(void Function(SkipSpanBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SkipSpanBuilder toBuilder() => SkipSpanBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SkipSpan &&
        startMs == other.startMs &&
        endMs == other.endMs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, startMs.hashCode);
    _$hash = $jc(_$hash, endMs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SkipSpan')
          ..add('startMs', startMs)
          ..add('endMs', endMs))
        .toString();
  }
}

class SkipSpanBuilder implements Builder<SkipSpan, SkipSpanBuilder> {
  _$SkipSpan? _$v;

  int? _startMs;
  int? get startMs => _$this._startMs;
  set startMs(int? startMs) => _$this._startMs = startMs;

  int? _endMs;
  int? get endMs => _$this._endMs;
  set endMs(int? endMs) => _$this._endMs = endMs;

  SkipSpanBuilder() {
    SkipSpan._defaults(this);
  }

  SkipSpanBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _startMs = $v.startMs;
      _endMs = $v.endMs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SkipSpan other) {
    _$v = other as _$SkipSpan;
  }

  @override
  void update(void Function(SkipSpanBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SkipSpan build() => _build();

  _$SkipSpan _build() {
    final _$result =
        _$v ??
        _$SkipSpan._(
          startMs: BuiltValueNullFieldError.checkNotNull(
            startMs,
            r'SkipSpan',
            'startMs',
          ),
          endMs: BuiltValueNullFieldError.checkNotNull(
            endMs,
            r'SkipSpan',
            'endMs',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
