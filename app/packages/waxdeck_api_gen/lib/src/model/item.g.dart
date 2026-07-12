// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Item extends Item {
  @override
  final int? discNumber;
  @override
  final DateTime? addedAt;
  @override
  final int? trackNumber;
  @override
  final int? year;
  @override
  final BuiltList<String>? genres;
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
  final int durationMs;
  @override
  final String? artUrl;

  factory _$Item([void Function(ItemBuilder)? updates]) =>
      (ItemBuilder()..update(updates))._build();

  _$Item._({
    this.discNumber,
    this.addedAt,
    this.trackNumber,
    this.year,
    this.genres,
    required this.pid,
    required this.mediaType,
    required this.title,
    this.artist,
    this.album,
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
        discNumber == other.discNumber &&
        addedAt == other.addedAt &&
        trackNumber == other.trackNumber &&
        year == other.year &&
        genres == other.genres &&
        pid == other.pid &&
        mediaType == other.mediaType &&
        title == other.title &&
        artist == other.artist &&
        album == other.album &&
        durationMs == other.durationMs &&
        artUrl == other.artUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, discNumber.hashCode);
    _$hash = $jc(_$hash, addedAt.hashCode);
    _$hash = $jc(_$hash, trackNumber.hashCode);
    _$hash = $jc(_$hash, year.hashCode);
    _$hash = $jc(_$hash, genres.hashCode);
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, album.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jc(_$hash, artUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Item')
          ..add('discNumber', discNumber)
          ..add('addedAt', addedAt)
          ..add('trackNumber', trackNumber)
          ..add('year', year)
          ..add('genres', genres)
          ..add('pid', pid)
          ..add('mediaType', mediaType)
          ..add('title', title)
          ..add('artist', artist)
          ..add('album', album)
          ..add('durationMs', durationMs)
          ..add('artUrl', artUrl))
        .toString();
  }
}

class ItemBuilder implements Builder<Item, ItemBuilder>, ItemSummaryBuilder {
  _$Item? _$v;

  int? _discNumber;
  int? get discNumber => _$this._discNumber;
  set discNumber(covariant int? discNumber) => _$this._discNumber = discNumber;

  DateTime? _addedAt;
  DateTime? get addedAt => _$this._addedAt;
  set addedAt(covariant DateTime? addedAt) => _$this._addedAt = addedAt;

  int? _trackNumber;
  int? get trackNumber => _$this._trackNumber;
  set trackNumber(covariant int? trackNumber) =>
      _$this._trackNumber = trackNumber;

  int? _year;
  int? get year => _$this._year;
  set year(covariant int? year) => _$this._year = year;

  ListBuilder<String>? _genres;
  ListBuilder<String> get genres => _$this._genres ??= ListBuilder<String>();
  set genres(covariant ListBuilder<String>? genres) => _$this._genres = genres;

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
      _discNumber = $v.discNumber;
      _addedAt = $v.addedAt;
      _trackNumber = $v.trackNumber;
      _year = $v.year;
      _genres = $v.genres?.toBuilder();
      _pid = $v.pid;
      _mediaType = $v.mediaType;
      _title = $v.title;
      _artist = $v.artist;
      _album = $v.album;
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
            discNumber: discNumber,
            addedAt: addedAt,
            trackNumber: trackNumber,
            year: year,
            genres: _genres?.build(),
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
