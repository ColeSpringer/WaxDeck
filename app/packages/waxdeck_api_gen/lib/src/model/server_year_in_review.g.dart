// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_year_in_review.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ServerYearInReview extends ServerYearInReview {
  @override
  final int year;
  @override
  final int participants;
  @override
  final int totalMs;
  @override
  final int sessions;
  @override
  final BuiltList<TopEntry> topArtists;
  @override
  final BuiltList<TopEntry> topTracks;
  @override
  final BuiltList<TopEntry> topGenres;

  factory _$ServerYearInReview([
    void Function(ServerYearInReviewBuilder)? updates,
  ]) => (ServerYearInReviewBuilder()..update(updates))._build();

  _$ServerYearInReview._({
    required this.year,
    required this.participants,
    required this.totalMs,
    required this.sessions,
    required this.topArtists,
    required this.topTracks,
    required this.topGenres,
  }) : super._();
  @override
  ServerYearInReview rebuild(
    void Function(ServerYearInReviewBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ServerYearInReviewBuilder toBuilder() =>
      ServerYearInReviewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServerYearInReview &&
        year == other.year &&
        participants == other.participants &&
        totalMs == other.totalMs &&
        sessions == other.sessions &&
        topArtists == other.topArtists &&
        topTracks == other.topTracks &&
        topGenres == other.topGenres;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, year.hashCode);
    _$hash = $jc(_$hash, participants.hashCode);
    _$hash = $jc(_$hash, totalMs.hashCode);
    _$hash = $jc(_$hash, sessions.hashCode);
    _$hash = $jc(_$hash, topArtists.hashCode);
    _$hash = $jc(_$hash, topTracks.hashCode);
    _$hash = $jc(_$hash, topGenres.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServerYearInReview')
          ..add('year', year)
          ..add('participants', participants)
          ..add('totalMs', totalMs)
          ..add('sessions', sessions)
          ..add('topArtists', topArtists)
          ..add('topTracks', topTracks)
          ..add('topGenres', topGenres))
        .toString();
  }
}

class ServerYearInReviewBuilder
    implements Builder<ServerYearInReview, ServerYearInReviewBuilder> {
  _$ServerYearInReview? _$v;

  int? _year;
  int? get year => _$this._year;
  set year(int? year) => _$this._year = year;

  int? _participants;
  int? get participants => _$this._participants;
  set participants(int? participants) => _$this._participants = participants;

  int? _totalMs;
  int? get totalMs => _$this._totalMs;
  set totalMs(int? totalMs) => _$this._totalMs = totalMs;

  int? _sessions;
  int? get sessions => _$this._sessions;
  set sessions(int? sessions) => _$this._sessions = sessions;

  ListBuilder<TopEntry>? _topArtists;
  ListBuilder<TopEntry> get topArtists =>
      _$this._topArtists ??= ListBuilder<TopEntry>();
  set topArtists(ListBuilder<TopEntry>? topArtists) =>
      _$this._topArtists = topArtists;

  ListBuilder<TopEntry>? _topTracks;
  ListBuilder<TopEntry> get topTracks =>
      _$this._topTracks ??= ListBuilder<TopEntry>();
  set topTracks(ListBuilder<TopEntry>? topTracks) =>
      _$this._topTracks = topTracks;

  ListBuilder<TopEntry>? _topGenres;
  ListBuilder<TopEntry> get topGenres =>
      _$this._topGenres ??= ListBuilder<TopEntry>();
  set topGenres(ListBuilder<TopEntry>? topGenres) =>
      _$this._topGenres = topGenres;

  ServerYearInReviewBuilder() {
    ServerYearInReview._defaults(this);
  }

  ServerYearInReviewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _year = $v.year;
      _participants = $v.participants;
      _totalMs = $v.totalMs;
      _sessions = $v.sessions;
      _topArtists = $v.topArtists.toBuilder();
      _topTracks = $v.topTracks.toBuilder();
      _topGenres = $v.topGenres.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServerYearInReview other) {
    _$v = other as _$ServerYearInReview;
  }

  @override
  void update(void Function(ServerYearInReviewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServerYearInReview build() => _build();

  _$ServerYearInReview _build() {
    _$ServerYearInReview _$result;
    try {
      _$result =
          _$v ??
          _$ServerYearInReview._(
            year: BuiltValueNullFieldError.checkNotNull(
              year,
              r'ServerYearInReview',
              'year',
            ),
            participants: BuiltValueNullFieldError.checkNotNull(
              participants,
              r'ServerYearInReview',
              'participants',
            ),
            totalMs: BuiltValueNullFieldError.checkNotNull(
              totalMs,
              r'ServerYearInReview',
              'totalMs',
            ),
            sessions: BuiltValueNullFieldError.checkNotNull(
              sessions,
              r'ServerYearInReview',
              'sessions',
            ),
            topArtists: topArtists.build(),
            topTracks: topTracks.build(),
            topGenres: topGenres.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'topArtists';
        topArtists.build();
        _$failedField = 'topTracks';
        topTracks.build();
        _$failedField = 'topGenres';
        topGenres.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ServerYearInReview',
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
