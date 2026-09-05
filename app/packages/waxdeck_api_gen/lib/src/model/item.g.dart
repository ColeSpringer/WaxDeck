// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Item extends Item {
  @override
  final String? container;
  @override
  final String? codec;
  @override
  final DateTime? addedAt;
  @override
  final ArtSource? artSource;
  @override
  final String? mbid;
  @override
  final int? year;
  @override
  final BuiltList<String>? genres;
  @override
  final int? bitrate;
  @override
  final String? isrc;
  @override
  final int? sampleRate;
  @override
  final int? bpm;
  @override
  final String pid;
  @override
  final MediaType mediaType;
  @override
  final String title;
  @override
  final String? artist;
  @override
  final String? album;
  @override
  final String? artistPid;
  @override
  final String? albumPid;
  @override
  final int? trackNumber;
  @override
  final int? discNumber;
  @override
  final int durationMs;
  @override
  final String? artUrl;

  factory _$Item([void Function(ItemBuilder)? updates]) =>
      (ItemBuilder()..update(updates))._build();

  _$Item._({
    this.container,
    this.codec,
    this.addedAt,
    this.artSource,
    this.mbid,
    this.year,
    this.genres,
    this.bitrate,
    this.isrc,
    this.sampleRate,
    this.bpm,
    required this.pid,
    required this.mediaType,
    required this.title,
    this.artist,
    this.album,
    this.artistPid,
    this.albumPid,
    this.trackNumber,
    this.discNumber,
    required this.durationMs,
    this.artUrl,
  }) : super._();
  @override
  Item rebuild(void Function(ItemBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ItemBuilder toBuilder() => ItemBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Item &&
        container == other.container &&
        codec == other.codec &&
        addedAt == other.addedAt &&
        artSource == other.artSource &&
        mbid == other.mbid &&
        year == other.year &&
        genres == other.genres &&
        bitrate == other.bitrate &&
        isrc == other.isrc &&
        sampleRate == other.sampleRate &&
        bpm == other.bpm &&
        pid == other.pid &&
        mediaType == other.mediaType &&
        title == other.title &&
        artist == other.artist &&
        album == other.album &&
        artistPid == other.artistPid &&
        albumPid == other.albumPid &&
        trackNumber == other.trackNumber &&
        discNumber == other.discNumber &&
        durationMs == other.durationMs &&
        artUrl == other.artUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, container.hashCode);
    _$hash = $jc(_$hash, codec.hashCode);
    _$hash = $jc(_$hash, addedAt.hashCode);
    _$hash = $jc(_$hash, artSource.hashCode);
    _$hash = $jc(_$hash, mbid.hashCode);
    _$hash = $jc(_$hash, year.hashCode);
    _$hash = $jc(_$hash, genres.hashCode);
    _$hash = $jc(_$hash, bitrate.hashCode);
    _$hash = $jc(_$hash, isrc.hashCode);
    _$hash = $jc(_$hash, sampleRate.hashCode);
    _$hash = $jc(_$hash, bpm.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, album.hashCode);
    _$hash = $jc(_$hash, artistPid.hashCode);
    _$hash = $jc(_$hash, albumPid.hashCode);
    _$hash = $jc(_$hash, trackNumber.hashCode);
    _$hash = $jc(_$hash, discNumber.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jc(_$hash, artUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Item')
          ..add('container', container)
          ..add('codec', codec)
          ..add('addedAt', addedAt)
          ..add('artSource', artSource)
          ..add('mbid', mbid)
          ..add('year', year)
          ..add('genres', genres)
          ..add('bitrate', bitrate)
          ..add('isrc', isrc)
          ..add('sampleRate', sampleRate)
          ..add('bpm', bpm)
          ..add('pid', pid)
          ..add('mediaType', mediaType)
          ..add('title', title)
          ..add('artist', artist)
          ..add('album', album)
          ..add('artistPid', artistPid)
          ..add('albumPid', albumPid)
          ..add('trackNumber', trackNumber)
          ..add('discNumber', discNumber)
          ..add('durationMs', durationMs)
          ..add('artUrl', artUrl))
        .toString();
  }
}

class ItemBuilder implements Builder<Item, ItemBuilder>, ItemSummaryBuilder {
  _$Item? _$v;

  String? _container;
  String? get container => _$this._container;
  set container(covariant String? container) => _$this._container = container;

  String? _codec;
  String? get codec => _$this._codec;
  set codec(covariant String? codec) => _$this._codec = codec;

  DateTime? _addedAt;
  DateTime? get addedAt => _$this._addedAt;
  set addedAt(covariant DateTime? addedAt) => _$this._addedAt = addedAt;

  ArtSourceBuilder? _artSource;
  ArtSourceBuilder get artSource => _$this._artSource ??= ArtSourceBuilder();
  set artSource(covariant ArtSourceBuilder? artSource) =>
      _$this._artSource = artSource;

  String? _mbid;
  String? get mbid => _$this._mbid;
  set mbid(covariant String? mbid) => _$this._mbid = mbid;

  int? _year;
  int? get year => _$this._year;
  set year(covariant int? year) => _$this._year = year;

  ListBuilder<String>? _genres;
  ListBuilder<String> get genres => _$this._genres ??= ListBuilder<String>();
  set genres(covariant ListBuilder<String>? genres) => _$this._genres = genres;

  int? _bitrate;
  int? get bitrate => _$this._bitrate;
  set bitrate(covariant int? bitrate) => _$this._bitrate = bitrate;

  String? _isrc;
  String? get isrc => _$this._isrc;
  set isrc(covariant String? isrc) => _$this._isrc = isrc;

  int? _sampleRate;
  int? get sampleRate => _$this._sampleRate;
  set sampleRate(covariant int? sampleRate) => _$this._sampleRate = sampleRate;

  int? _bpm;
  int? get bpm => _$this._bpm;
  set bpm(covariant int? bpm) => _$this._bpm = bpm;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(covariant String? pid) => _$this._pid = pid;

  MediaType? _mediaType;
  MediaType? get mediaType => _$this._mediaType;
  set mediaType(covariant MediaType? mediaType) =>
      _$this._mediaType = mediaType;

  String? _title;
  String? get title => _$this._title;
  set title(covariant String? title) => _$this._title = title;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(covariant String? artist) => _$this._artist = artist;

  String? _album;
  String? get album => _$this._album;
  set album(covariant String? album) => _$this._album = album;

  String? _artistPid;
  String? get artistPid => _$this._artistPid;
  set artistPid(covariant String? artistPid) => _$this._artistPid = artistPid;

  String? _albumPid;
  String? get albumPid => _$this._albumPid;
  set albumPid(covariant String? albumPid) => _$this._albumPid = albumPid;

  int? _trackNumber;
  int? get trackNumber => _$this._trackNumber;
  set trackNumber(covariant int? trackNumber) =>
      _$this._trackNumber = trackNumber;

  int? _discNumber;
  int? get discNumber => _$this._discNumber;
  set discNumber(covariant int? discNumber) => _$this._discNumber = discNumber;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(covariant int? durationMs) => _$this._durationMs = durationMs;

  String? _artUrl;
  String? get artUrl => _$this._artUrl;
  set artUrl(covariant String? artUrl) => _$this._artUrl = artUrl;

  ItemBuilder() {
    Item._defaults(this);
  }

  ItemBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _container = $v.container;
      _codec = $v.codec;
      _addedAt = $v.addedAt;
      _artSource = $v.artSource?.toBuilder();
      _mbid = $v.mbid;
      _year = $v.year;
      _genres = $v.genres?.toBuilder();
      _bitrate = $v.bitrate;
      _isrc = $v.isrc;
      _sampleRate = $v.sampleRate;
      _bpm = $v.bpm;
      _pid = $v.pid;
      _mediaType = $v.mediaType;
      _title = $v.title;
      _artist = $v.artist;
      _album = $v.album;
      _artistPid = $v.artistPid;
      _albumPid = $v.albumPid;
      _trackNumber = $v.trackNumber;
      _discNumber = $v.discNumber;
      _durationMs = $v.durationMs;
      _artUrl = $v.artUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant Item other) {
    _$v = other as _$Item;
  }

  @override
  void update(void Function(ItemBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Item build() => _build();

  _$Item _build() {
    _$Item _$result;
    try {
      _$result =
          _$v ??
          _$Item._(
            container: container,
            codec: codec,
            addedAt: addedAt,
            artSource: _artSource?.build(),
            mbid: mbid,
            year: year,
            genres: _genres?.build(),
            bitrate: bitrate,
            isrc: isrc,
            sampleRate: sampleRate,
            bpm: bpm,
            pid: BuiltValueNullFieldError.checkNotNull(pid, r'Item', 'pid'),
            mediaType: BuiltValueNullFieldError.checkNotNull(
              mediaType,
              r'Item',
              'mediaType',
            ),
            title: BuiltValueNullFieldError.checkNotNull(
              title,
              r'Item',
              'title',
            ),
            artist: artist,
            album: album,
            artistPid: artistPid,
            albumPid: albumPid,
            trackNumber: trackNumber,
            discNumber: discNumber,
            durationMs: BuiltValueNullFieldError.checkNotNull(
              durationMs,
              r'Item',
              'durationMs',
            ),
            artUrl: artUrl,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'artSource';
        _artSource?.build();

        _$failedField = 'genres';
        _genres?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'Item', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
