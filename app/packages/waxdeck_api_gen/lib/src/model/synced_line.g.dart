// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'synced_line.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SyncedLine extends SyncedLine {
  @override
  final int timeMs;
  @override
  final String text;

  factory _$SyncedLine([void Function(SyncedLineBuilder)? updates]) =>
      (SyncedLineBuilder()..update(updates))._build();

  _$SyncedLine._({required this.timeMs, required this.text}) : super._();
  @override
  SyncedLine rebuild(void Function(SyncedLineBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SyncedLineBuilder toBuilder() => SyncedLineBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SyncedLine && timeMs == other.timeMs && text == other.text;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, timeMs.hashCode);
    _$hash = $jc(_$hash, text.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SyncedLine')
          ..add('timeMs', timeMs)
          ..add('text', text))
        .toString();
  }
}

class SyncedLineBuilder implements Builder<SyncedLine, SyncedLineBuilder> {
  _$SyncedLine? _$v;

  int? _timeMs;
  int? get timeMs => _$this._timeMs;
  set timeMs(int? timeMs) => _$this._timeMs = timeMs;

  String? _text;
  String? get text => _$this._text;
  set text(String? text) => _$this._text = text;

  SyncedLineBuilder() {
    SyncedLine._defaults(this);
  }

  SyncedLineBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _timeMs = $v.timeMs;
      _text = $v.text;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SyncedLine other) {
    _$v = other as _$SyncedLine;
  }

  @override
  void update(void Function(SyncedLineBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SyncedLine build() => _build();

  _$SyncedLine _build() {
    final _$result =
        _$v ??
        _$SyncedLine._(
          timeMs: BuiltValueNullFieldError.checkNotNull(
            timeMs,
            r'SyncedLine',
            'timeMs',
          ),
          text: BuiltValueNullFieldError.checkNotNull(
            text,
            r'SyncedLine',
            'text',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
