// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcript.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Transcript extends Transcript {
  @override
  final String format;
  @override
  final BuiltList<TranscriptCue> cues;

  factory _$Transcript([void Function(TranscriptBuilder)? updates]) =>
      (TranscriptBuilder()..update(updates))._build();

  _$Transcript._({required this.format, required this.cues}) : super._();
  @override
  Transcript rebuild(void Function(TranscriptBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TranscriptBuilder toBuilder() => TranscriptBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Transcript && format == other.format && cues == other.cues;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, format.hashCode);
    _$hash = $jc(_$hash, cues.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Transcript')
          ..add('format', format)
          ..add('cues', cues))
        .toString();
  }
}

class TranscriptBuilder implements Builder<Transcript, TranscriptBuilder> {
  _$Transcript? _$v;

  String? _format;
  String? get format => _$this._format;
  set format(String? format) => _$this._format = format;

  ListBuilder<TranscriptCue>? _cues;
  ListBuilder<TranscriptCue> get cues =>
      _$this._cues ??= ListBuilder<TranscriptCue>();
  set cues(ListBuilder<TranscriptCue>? cues) => _$this._cues = cues;

  TranscriptBuilder() {
    Transcript._defaults(this);
  }

  TranscriptBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _format = $v.format;
      _cues = $v.cues.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Transcript other) {
    _$v = other as _$Transcript;
  }

  @override
  void update(void Function(TranscriptBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Transcript build() => _build();

  _$Transcript _build() {
    _$Transcript _$result;
    try {
      _$result =
          _$v ??
          _$Transcript._(
            format: BuiltValueNullFieldError.checkNotNull(
              format,
              r'Transcript',
              'format',
            ),
            cues: cues.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'cues';
        cues.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'Transcript',
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
