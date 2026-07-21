// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_session_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaybackSessionEntry extends PlaybackSessionEntry {
  @override
  final String pid;
  @override
  final String title;
  @override
  final String? artist;
  @override
  final int? durationMs;

  factory _$PlaybackSessionEntry([
    void Function(PlaybackSessionEntryBuilder)? updates,
  ]) => (PlaybackSessionEntryBuilder()..update(updates))._build();

  _$PlaybackSessionEntry._({
    required this.pid,
    required this.title,
    this.artist,
    this.durationMs,
  }) : super._();
  @override
  PlaybackSessionEntry rebuild(
    void Function(PlaybackSessionEntryBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaybackSessionEntryBuilder toBuilder() =>
      PlaybackSessionEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaybackSessionEntry &&
        pid == other.pid &&
        title == other.title &&
        artist == other.artist &&
        durationMs == other.durationMs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaybackSessionEntry')
          ..add('pid', pid)
          ..add('title', title)
          ..add('artist', artist)
          ..add('durationMs', durationMs))
        .toString();
  }
}

class PlaybackSessionEntryBuilder
    implements Builder<PlaybackSessionEntry, PlaybackSessionEntryBuilder> {
  _$PlaybackSessionEntry? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  PlaybackSessionEntryBuilder() {
    PlaybackSessionEntry._defaults(this);
  }

  PlaybackSessionEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _title = $v.title;
      _artist = $v.artist;
      _durationMs = $v.durationMs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaybackSessionEntry other) {
    _$v = other as _$PlaybackSessionEntry;
  }

  @override
  void update(void Function(PlaybackSessionEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaybackSessionEntry build() => _build();

  _$PlaybackSessionEntry _build() {
    final _$result =
        _$v ??
        _$PlaybackSessionEntry._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'PlaybackSessionEntry',
            'pid',
          ),
          title: BuiltValueNullFieldError.checkNotNull(
            title,
            r'PlaybackSessionEntry',
            'title',
          ),
          artist: artist,
          durationMs: durationMs,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
