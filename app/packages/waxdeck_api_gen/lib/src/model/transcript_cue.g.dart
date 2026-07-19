// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcript_cue.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TranscriptCue extends TranscriptCue {
  @override
  final int startMs;
  @override
  final int? endMs;
  @override
  final String text;
  @override
  final String? speaker;

  factory _$TranscriptCue([void Function(TranscriptCueBuilder)? updates]) =>
      (TranscriptCueBuilder()..update(updates))._build();

  _$TranscriptCue._({
    required this.startMs,
    this.endMs,
    required this.text,
    this.speaker,
  }) : super._();
  @override
  TranscriptCue rebuild(void Function(TranscriptCueBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TranscriptCueBuilder toBuilder() => TranscriptCueBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TranscriptCue &&
        startMs == other.startMs &&
        endMs == other.endMs &&
        text == other.text &&
        speaker == other.speaker;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, startMs.hashCode);
    _$hash = $jc(_$hash, endMs.hashCode);
    _$hash = $jc(_$hash, text.hashCode);
    _$hash = $jc(_$hash, speaker.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TranscriptCue')
          ..add('startMs', startMs)
          ..add('endMs', endMs)
          ..add('text', text)
          ..add('speaker', speaker))
        .toString();
  }
}

class TranscriptCueBuilder
    implements Builder<TranscriptCue, TranscriptCueBuilder> {
  _$TranscriptCue? _$v;

  int? _startMs;
  int? get startMs => _$this._startMs;
  set startMs(int? startMs) => _$this._startMs = startMs;

  int? _endMs;
  int? get endMs => _$this._endMs;
  set endMs(int? endMs) => _$this._endMs = endMs;

  String? _text;
  String? get text => _$this._text;
  set text(String? text) => _$this._text = text;

  String? _speaker;
  String? get speaker => _$this._speaker;
  set speaker(String? speaker) => _$this._speaker = speaker;

  TranscriptCueBuilder() {
    TranscriptCue._defaults(this);
  }

  TranscriptCueBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _startMs = $v.startMs;
      _endMs = $v.endMs;
      _text = $v.text;
      _speaker = $v.speaker;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TranscriptCue other) {
    _$v = other as _$TranscriptCue;
  }

  @override
  void update(void Function(TranscriptCueBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TranscriptCue build() => _build();

  _$TranscriptCue _build() {
    final _$result =
        _$v ??
        _$TranscriptCue._(
          startMs: BuiltValueNullFieldError.checkNotNull(
            startMs,
            r'TranscriptCue',
            'startMs',
          ),
          endMs: endMs,
          text: BuiltValueNullFieldError.checkNotNull(
            text,
            r'TranscriptCue',
            'text',
          ),
          speaker: speaker,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
