// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_import_miss.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaylistImportMiss extends PlaylistImportMiss {
  @override
  final String? artist;
  @override
  final String title;
  @override
  final String? album;
  @override
  final int? durationMs;

  factory _$PlaylistImportMiss([
    void Function(PlaylistImportMissBuilder)? updates,
  ]) => (PlaylistImportMissBuilder()..update(updates))._build();

  _$PlaylistImportMiss._({
    this.artist,
    required this.title,
    this.album,
    this.durationMs,
  }) : super._();
  @override
  PlaylistImportMiss rebuild(
    void Function(PlaylistImportMissBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaylistImportMissBuilder toBuilder() =>
      PlaylistImportMissBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistImportMiss &&
        artist == other.artist &&
        title == other.title &&
        album == other.album &&
        durationMs == other.durationMs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, album.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistImportMiss')
          ..add('artist', artist)
          ..add('title', title)
          ..add('album', album)
          ..add('durationMs', durationMs))
        .toString();
  }
}

class PlaylistImportMissBuilder
    implements Builder<PlaylistImportMiss, PlaylistImportMissBuilder> {
  _$PlaylistImportMiss? _$v;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _album;
  String? get album => _$this._album;
  set album(String? album) => _$this._album = album;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  PlaylistImportMissBuilder() {
    PlaylistImportMiss._defaults(this);
  }

  PlaylistImportMissBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _artist = $v.artist;
      _title = $v.title;
      _album = $v.album;
      _durationMs = $v.durationMs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistImportMiss other) {
    _$v = other as _$PlaylistImportMiss;
  }

  @override
  void update(void Function(PlaylistImportMissBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistImportMiss build() => _build();

  _$PlaylistImportMiss _build() {
    final _$result =
        _$v ??
        _$PlaylistImportMiss._(
          artist: artist,
          title: BuiltValueNullFieldError.checkNotNull(
            title,
            r'PlaylistImportMiss',
            'title',
          ),
          album: album,
          durationMs: durationMs,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
