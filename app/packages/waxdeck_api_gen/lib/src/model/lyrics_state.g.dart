// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lyrics_state.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LyricsState extends LyricsState {
  @override
  final bool synced;
  @override
  final String source_;
  @override
  final String? lrc;

  factory _$LyricsState([void Function(LyricsStateBuilder)? updates]) =>
      (LyricsStateBuilder()..update(updates))._build();

  _$LyricsState._({required this.synced, required this.source_, this.lrc})
    : super._();
  @override
  LyricsState rebuild(void Function(LyricsStateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LyricsStateBuilder toBuilder() => LyricsStateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LyricsState &&
        synced == other.synced &&
        source_ == other.source_ &&
        lrc == other.lrc;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, synced.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, lrc.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LyricsState')
          ..add('synced', synced)
          ..add('source_', source_)
          ..add('lrc', lrc))
        .toString();
  }
}

class LyricsStateBuilder implements Builder<LyricsState, LyricsStateBuilder> {
  _$LyricsState? _$v;

  bool? _synced;
  bool? get synced => _$this._synced;
  set synced(bool? synced) => _$this._synced = synced;

  String? _source_;
  String? get source_ => _$this._source_;
  set source_(String? source_) => _$this._source_ = source_;

  String? _lrc;
  String? get lrc => _$this._lrc;
  set lrc(String? lrc) => _$this._lrc = lrc;

  LyricsStateBuilder() {
    LyricsState._defaults(this);
  }

  LyricsStateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _synced = $v.synced;
      _source_ = $v.source_;
      _lrc = $v.lrc;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LyricsState other) {
    _$v = other as _$LyricsState;
  }

  @override
  void update(void Function(LyricsStateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LyricsState build() => _build();

  _$LyricsState _build() {
    final _$result =
        _$v ??
        _$LyricsState._(
          synced: BuiltValueNullFieldError.checkNotNull(
            synced,
            r'LyricsState',
            'synced',
          ),
          source_: BuiltValueNullFieldError.checkNotNull(
            source_,
            r'LyricsState',
            'source_',
          ),
          lrc: lrc,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
