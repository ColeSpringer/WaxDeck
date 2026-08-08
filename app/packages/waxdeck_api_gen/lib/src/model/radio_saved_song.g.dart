// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radio_saved_song.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RadioSavedSong extends RadioSavedSong {
  @override
  final String pid;
  @override
  final String nowPlaying;
  @override
  final String? artist;
  @override
  final String? title;
  @override
  final String? stationPid;
  @override
  final String stationName;
  @override
  final DateTime heardAt;
  @override
  final String? inLibraryPid;
  @override
  final bool hasArt;

  factory _$RadioSavedSong([void Function(RadioSavedSongBuilder)? updates]) =>
      (RadioSavedSongBuilder()..update(updates))._build();

  _$RadioSavedSong._({
    required this.pid,
    required this.nowPlaying,
    this.artist,
    this.title,
    this.stationPid,
    required this.stationName,
    required this.heardAt,
    this.inLibraryPid,
    required this.hasArt,
  }) : super._();
  @override
  RadioSavedSong rebuild(void Function(RadioSavedSongBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RadioSavedSongBuilder toBuilder() => RadioSavedSongBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RadioSavedSong &&
        pid == other.pid &&
        nowPlaying == other.nowPlaying &&
        artist == other.artist &&
        title == other.title &&
        stationPid == other.stationPid &&
        stationName == other.stationName &&
        heardAt == other.heardAt &&
        inLibraryPid == other.inLibraryPid &&
        hasArt == other.hasArt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, nowPlaying.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, stationPid.hashCode);
    _$hash = $jc(_$hash, stationName.hashCode);
    _$hash = $jc(_$hash, heardAt.hashCode);
    _$hash = $jc(_$hash, inLibraryPid.hashCode);
    _$hash = $jc(_$hash, hasArt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RadioSavedSong')
          ..add('pid', pid)
          ..add('nowPlaying', nowPlaying)
          ..add('artist', artist)
          ..add('title', title)
          ..add('stationPid', stationPid)
          ..add('stationName', stationName)
          ..add('heardAt', heardAt)
          ..add('inLibraryPid', inLibraryPid)
          ..add('hasArt', hasArt))
        .toString();
  }
}

class RadioSavedSongBuilder
    implements Builder<RadioSavedSong, RadioSavedSongBuilder> {
  _$RadioSavedSong? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _nowPlaying;
  String? get nowPlaying => _$this._nowPlaying;
  set nowPlaying(String? nowPlaying) => _$this._nowPlaying = nowPlaying;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _stationPid;
  String? get stationPid => _$this._stationPid;
  set stationPid(String? stationPid) => _$this._stationPid = stationPid;

  String? _stationName;
  String? get stationName => _$this._stationName;
  set stationName(String? stationName) => _$this._stationName = stationName;

  DateTime? _heardAt;
  DateTime? get heardAt => _$this._heardAt;
  set heardAt(DateTime? heardAt) => _$this._heardAt = heardAt;

  String? _inLibraryPid;
  String? get inLibraryPid => _$this._inLibraryPid;
  set inLibraryPid(String? inLibraryPid) => _$this._inLibraryPid = inLibraryPid;

  bool? _hasArt;
  bool? get hasArt => _$this._hasArt;
  set hasArt(bool? hasArt) => _$this._hasArt = hasArt;

  RadioSavedSongBuilder() {
    RadioSavedSong._defaults(this);
  }

  RadioSavedSongBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _nowPlaying = $v.nowPlaying;
      _artist = $v.artist;
      _title = $v.title;
      _stationPid = $v.stationPid;
      _stationName = $v.stationName;
      _heardAt = $v.heardAt;
      _inLibraryPid = $v.inLibraryPid;
      _hasArt = $v.hasArt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RadioSavedSong other) {
    _$v = other as _$RadioSavedSong;
  }

  @override
  void update(void Function(RadioSavedSongBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RadioSavedSong build() => _build();

  _$RadioSavedSong _build() {
    final _$result =
        _$v ??
        _$RadioSavedSong._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'RadioSavedSong',
            'pid',
          ),
          nowPlaying: BuiltValueNullFieldError.checkNotNull(
            nowPlaying,
            r'RadioSavedSong',
            'nowPlaying',
          ),
          artist: artist,
          title: title,
          stationPid: stationPid,
          stationName: BuiltValueNullFieldError.checkNotNull(
            stationName,
            r'RadioSavedSong',
            'stationName',
          ),
          heardAt: BuiltValueNullFieldError.checkNotNull(
            heardAt,
            r'RadioSavedSong',
            'heardAt',
          ),
          inLibraryPid: inLibraryPid,
          hasArt: BuiltValueNullFieldError.checkNotNull(
            hasArt,
            r'RadioSavedSong',
            'hasArt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
