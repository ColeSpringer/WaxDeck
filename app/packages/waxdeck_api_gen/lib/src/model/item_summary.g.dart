// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item_summary.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

abstract mixin class ItemSummaryBuilder {
  void replace(ItemSummary other);
  void update(void Function(ItemSummaryBuilder) updates);
  String? get pid;
  set pid(String? pid);

  MediaType? get mediaType;
  set mediaType(MediaType? mediaType);

  String? get title;
  set title(String? title);

  String? get artist;
  set artist(String? artist);

  String? get album;
  set album(String? album);

  int? get durationMs;
  set durationMs(int? durationMs);

  String? get artUrl;
  set artUrl(String? artUrl);
}

class _$$ItemSummary extends $ItemSummary {
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

  factory _$$ItemSummary([void Function($ItemSummaryBuilder)? updates]) =>
      ($ItemSummaryBuilder()..update(updates))._build();

  _$$ItemSummary._({
    required this.pid,
    required this.mediaType,
    required this.title,
    this.artist,
    this.album,
    required this.durationMs,
    this.artUrl,
  }) : super._();
  @override
  $ItemSummary rebuild(void Function($ItemSummaryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  $ItemSummaryBuilder toBuilder() => $ItemSummaryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is $ItemSummary &&
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
    return (newBuiltValueToStringHelper(r'$ItemSummary')
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

class $ItemSummaryBuilder
    implements Builder<$ItemSummary, $ItemSummaryBuilder>, ItemSummaryBuilder {
  _$$ItemSummary? _$v;

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

  $ItemSummaryBuilder() {
    $ItemSummary._defaults(this);
  }

  $ItemSummaryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
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
  void replace(covariant $ItemSummary other) {
    _$v = other as _$$ItemSummary;
  }

  @override
  void update(void Function($ItemSummaryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  $ItemSummary build() => _build();

  _$$ItemSummary _build() {
    final _$result =
        _$v ??
        _$$ItemSummary._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'$ItemSummary',
            'pid',
          ),
          mediaType: BuiltValueNullFieldError.checkNotNull(
            mediaType,
            r'$ItemSummary',
            'mediaType',
          ),
          title: BuiltValueNullFieldError.checkNotNull(
            title,
            r'$ItemSummary',
            'title',
          ),
          artist: artist,
          album: album,
          durationMs: BuiltValueNullFieldError.checkNotNull(
            durationMs,
            r'$ItemSummary',
            'durationMs',
          ),
          artUrl: artUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
