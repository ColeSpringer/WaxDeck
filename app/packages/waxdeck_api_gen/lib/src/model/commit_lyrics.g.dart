// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'commit_lyrics.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CommitLyrics extends CommitLyrics {
  @override
  final String? lrc;
  @override
  final String? plain;

  factory _$CommitLyrics([void Function(CommitLyricsBuilder)? updates]) =>
      (CommitLyricsBuilder()..update(updates))._build();

  _$CommitLyrics._({this.lrc, this.plain}) : super._();
  @override
  CommitLyrics rebuild(void Function(CommitLyricsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CommitLyricsBuilder toBuilder() => CommitLyricsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CommitLyrics && lrc == other.lrc && plain == other.plain;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, lrc.hashCode);
    _$hash = $jc(_$hash, plain.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CommitLyrics')
          ..add('lrc', lrc)
          ..add('plain', plain))
        .toString();
  }
}

class CommitLyricsBuilder
    implements Builder<CommitLyrics, CommitLyricsBuilder> {
  _$CommitLyrics? _$v;

  String? _lrc;
  String? get lrc => _$this._lrc;
  set lrc(String? lrc) => _$this._lrc = lrc;

  String? _plain;
  String? get plain => _$this._plain;
  set plain(String? plain) => _$this._plain = plain;

  CommitLyricsBuilder() {
    CommitLyrics._defaults(this);
  }

  CommitLyricsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _lrc = $v.lrc;
      _plain = $v.plain;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CommitLyrics other) {
    _$v = other as _$CommitLyrics;
  }

  @override
  void update(void Function(CommitLyricsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CommitLyrics build() => _build();

  _$CommitLyrics _build() {
    final _$result = _$v ?? _$CommitLyrics._(lrc: lrc, plain: plain);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
