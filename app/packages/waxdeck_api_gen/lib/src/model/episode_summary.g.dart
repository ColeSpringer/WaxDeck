// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'episode_summary.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

abstract mixin class EpisodeSummaryBuilder implements ItemSummaryBuilder {
  void replace(covariant EpisodeSummary other);
  void update(void Function(EpisodeSummaryBuilder) updates);
  bool? get explicit;
  set explicit(covariant bool? explicit);

  String? get episodeType;
  set episodeType(covariant String? episodeType);

  String? get fetchError;
  set fetchError(covariant String? fetchError);

  String? get fetchState;
  set fetchState(covariant String? fetchState);

  DateTime? get publishedAt;
  set publishedAt(covariant DateTime? publishedAt);

  String? get showPid;
  set showPid(covariant String? showPid);

  int? get season;
  set season(covariant int? season);

  int? get episodeNumber;
  set episodeNumber(covariant int? episodeNumber);

  bool? get downloaded;
  set downloaded(covariant bool? downloaded);

  bool? get hasTranscript;
  set hasTranscript(covariant bool? hasTranscript);

  String? get pid;
  set pid(covariant String? pid);

  MediaType? get mediaType;
  set mediaType(covariant MediaType? mediaType);

  String? get title;
  set title(covariant String? title);

  String? get artist;
  set artist(covariant String? artist);

  String? get album;
  set album(covariant String? album);

  int? get durationMs;
  set durationMs(covariant int? durationMs);

  String? get artUrl;
  set artUrl(covariant String? artUrl);
}

class _$$EpisodeSummary extends $EpisodeSummary {
  @override
  final bool? explicit;
  @override
  final String? episodeType;
  @override
  final String? fetchError;
  @override
  final String? fetchState;
  @override
  final DateTime publishedAt;
  @override
  final String showPid;
  @override
  final int? season;
  @override
  final int? episodeNumber;
  @override
  final bool downloaded;
  @override
  final bool? hasTranscript;
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

  factory _$$EpisodeSummary([void Function($EpisodeSummaryBuilder)? updates]) =>
      ($EpisodeSummaryBuilder()..update(updates))._build();

  _$$EpisodeSummary._({
    this.explicit,
    this.episodeType,
    this.fetchError,
    this.fetchState,
    required this.publishedAt,
    required this.showPid,
    this.season,
    this.episodeNumber,
    required this.downloaded,
    this.hasTranscript,
    required this.pid,
    required this.mediaType,
    required this.title,
    this.artist,
    this.album,
    required this.durationMs,
    this.artUrl,
  }) : super._();
  @override
  $EpisodeSummary rebuild(void Function($EpisodeSummaryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  $EpisodeSummaryBuilder toBuilder() => $EpisodeSummaryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is $EpisodeSummary &&
        explicit == other.explicit &&
        episodeType == other.episodeType &&
        fetchError == other.fetchError &&
        fetchState == other.fetchState &&
        publishedAt == other.publishedAt &&
        showPid == other.showPid &&
        season == other.season &&
        episodeNumber == other.episodeNumber &&
        downloaded == other.downloaded &&
        hasTranscript == other.hasTranscript &&
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
    _$hash = $jc(_$hash, explicit.hashCode);
    _$hash = $jc(_$hash, episodeType.hashCode);
    _$hash = $jc(_$hash, fetchError.hashCode);
    _$hash = $jc(_$hash, fetchState.hashCode);
    _$hash = $jc(_$hash, publishedAt.hashCode);
    _$hash = $jc(_$hash, showPid.hashCode);
    _$hash = $jc(_$hash, season.hashCode);
    _$hash = $jc(_$hash, episodeNumber.hashCode);
    _$hash = $jc(_$hash, downloaded.hashCode);
    _$hash = $jc(_$hash, hasTranscript.hashCode);
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
    return (newBuiltValueToStringHelper(r'$EpisodeSummary')
          ..add('explicit', explicit)
          ..add('episodeType', episodeType)
          ..add('fetchError', fetchError)
          ..add('fetchState', fetchState)
          ..add('publishedAt', publishedAt)
          ..add('showPid', showPid)
          ..add('season', season)
          ..add('episodeNumber', episodeNumber)
          ..add('downloaded', downloaded)
          ..add('hasTranscript', hasTranscript)
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

class $EpisodeSummaryBuilder
    implements
        Builder<$EpisodeSummary, $EpisodeSummaryBuilder>,
        EpisodeSummaryBuilder {
  _$$EpisodeSummary? _$v;

  bool? _explicit;
  bool? get explicit => _$this._explicit;
  set explicit(covariant bool? explicit) => _$this._explicit = explicit;

  String? _episodeType;
  String? get episodeType => _$this._episodeType;
  set episodeType(covariant String? episodeType) =>
      _$this._episodeType = episodeType;

  String? _fetchError;
  String? get fetchError => _$this._fetchError;
  set fetchError(covariant String? fetchError) =>
      _$this._fetchError = fetchError;

  String? _fetchState;
  String? get fetchState => _$this._fetchState;
  set fetchState(covariant String? fetchState) =>
      _$this._fetchState = fetchState;

  DateTime? _publishedAt;
  DateTime? get publishedAt => _$this._publishedAt;
  set publishedAt(covariant DateTime? publishedAt) =>
      _$this._publishedAt = publishedAt;

  String? _showPid;
  String? get showPid => _$this._showPid;
  set showPid(covariant String? showPid) => _$this._showPid = showPid;

  int? _season;
  int? get season => _$this._season;
  set season(covariant int? season) => _$this._season = season;

  int? _episodeNumber;
  int? get episodeNumber => _$this._episodeNumber;
  set episodeNumber(covariant int? episodeNumber) =>
      _$this._episodeNumber = episodeNumber;

  bool? _downloaded;
  bool? get downloaded => _$this._downloaded;
  set downloaded(covariant bool? downloaded) => _$this._downloaded = downloaded;

  bool? _hasTranscript;
  bool? get hasTranscript => _$this._hasTranscript;
  set hasTranscript(covariant bool? hasTranscript) =>
      _$this._hasTranscript = hasTranscript;

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

  $EpisodeSummaryBuilder() {
    $EpisodeSummary._defaults(this);
  }

  $EpisodeSummaryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _explicit = $v.explicit;
      _episodeType = $v.episodeType;
      _fetchError = $v.fetchError;
      _fetchState = $v.fetchState;
      _publishedAt = $v.publishedAt;
      _showPid = $v.showPid;
      _season = $v.season;
      _episodeNumber = $v.episodeNumber;
      _downloaded = $v.downloaded;
      _hasTranscript = $v.hasTranscript;
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
  void replace(covariant $EpisodeSummary other) {
    _$v = other as _$$EpisodeSummary;
  }

  @override
  void update(void Function($EpisodeSummaryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  $EpisodeSummary build() => _build();

  _$$EpisodeSummary _build() {
    final _$result =
        _$v ??
        _$$EpisodeSummary._(
          explicit: explicit,
          episodeType: episodeType,
          fetchError: fetchError,
          fetchState: fetchState,
          publishedAt: BuiltValueNullFieldError.checkNotNull(
            publishedAt,
            r'$EpisodeSummary',
            'publishedAt',
          ),
          showPid: BuiltValueNullFieldError.checkNotNull(
            showPid,
            r'$EpisodeSummary',
            'showPid',
          ),
          season: season,
          episodeNumber: episodeNumber,
          downloaded: BuiltValueNullFieldError.checkNotNull(
            downloaded,
            r'$EpisodeSummary',
            'downloaded',
          ),
          hasTranscript: hasTranscript,
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'$EpisodeSummary',
            'pid',
          ),
          mediaType: BuiltValueNullFieldError.checkNotNull(
            mediaType,
            r'$EpisodeSummary',
            'mediaType',
          ),
          title: BuiltValueNullFieldError.checkNotNull(
            title,
            r'$EpisodeSummary',
            'title',
          ),
          artist: artist,
          album: album,
          durationMs: BuiltValueNullFieldError.checkNotNull(
            durationMs,
            r'$EpisodeSummary',
            'durationMs',
          ),
          artUrl: artUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
