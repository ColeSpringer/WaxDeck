// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'year_in_review.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$YearInReview extends YearInReview {
  @override
  final int year;
  @override
  final String timezone;
  @override
  final int totalMs;
  @override
  final int sessions;
  @override
  final int distinctItems;
  @override
  final int newInLibrary;
  @override
  final int timeSavedMs;
  @override
  final int longestStreakDays;
  @override
  final BuiltList<MonthListening> byMonth;
  @override
  final BuiltList<MediaTypeListening> byMediaType;
  @override
  final BuiltList<TopEntry> topArtists;
  @override
  final BuiltList<TopEntry> topTracks;
  @override
  final BuiltList<TopEntry> topGenres;
  @override
  final BuiltList<TopEntry> topShows;

  factory _$YearInReview([void Function(YearInReviewBuilder)? updates]) =>
      (YearInReviewBuilder()..update(updates))._build();

  _$YearInReview._({
    required this.year,
    required this.timezone,
    required this.totalMs,
    required this.sessions,
    required this.distinctItems,
    required this.newInLibrary,
    required this.timeSavedMs,
    required this.longestStreakDays,
    required this.byMonth,
    required this.byMediaType,
    required this.topArtists,
    required this.topTracks,
    required this.topGenres,
    required this.topShows,
  }) : super._();
  @override
  YearInReview rebuild(void Function(YearInReviewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  YearInReviewBuilder toBuilder() => YearInReviewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is YearInReview &&
        year == other.year &&
        timezone == other.timezone &&
        totalMs == other.totalMs &&
        sessions == other.sessions &&
        distinctItems == other.distinctItems &&
        newInLibrary == other.newInLibrary &&
        timeSavedMs == other.timeSavedMs &&
        longestStreakDays == other.longestStreakDays &&
        byMonth == other.byMonth &&
        byMediaType == other.byMediaType &&
        topArtists == other.topArtists &&
        topTracks == other.topTracks &&
        topGenres == other.topGenres &&
        topShows == other.topShows;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, year.hashCode);
    _$hash = $jc(_$hash, timezone.hashCode);
    _$hash = $jc(_$hash, totalMs.hashCode);
    _$hash = $jc(_$hash, sessions.hashCode);
    _$hash = $jc(_$hash, distinctItems.hashCode);
    _$hash = $jc(_$hash, newInLibrary.hashCode);
    _$hash = $jc(_$hash, timeSavedMs.hashCode);
    _$hash = $jc(_$hash, longestStreakDays.hashCode);
    _$hash = $jc(_$hash, byMonth.hashCode);
    _$hash = $jc(_$hash, byMediaType.hashCode);
    _$hash = $jc(_$hash, topArtists.hashCode);
    _$hash = $jc(_$hash, topTracks.hashCode);
    _$hash = $jc(_$hash, topGenres.hashCode);
    _$hash = $jc(_$hash, topShows.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'YearInReview')
          ..add('year', year)
          ..add('timezone', timezone)
          ..add('totalMs', totalMs)
          ..add('sessions', sessions)
          ..add('distinctItems', distinctItems)
          ..add('newInLibrary', newInLibrary)
          ..add('timeSavedMs', timeSavedMs)
          ..add('longestStreakDays', longestStreakDays)
          ..add('byMonth', byMonth)
          ..add('byMediaType', byMediaType)
          ..add('topArtists', topArtists)
          ..add('topTracks', topTracks)
          ..add('topGenres', topGenres)
          ..add('topShows', topShows))
        .toString();
  }
}

class YearInReviewBuilder
    implements Builder<YearInReview, YearInReviewBuilder> {
  _$YearInReview? _$v;

  int? _year;
  int? get year => _$this._year;
  set year(int? year) => _$this._year = year;

  String? _timezone;
  String? get timezone => _$this._timezone;
  set timezone(String? timezone) => _$this._timezone = timezone;

  int? _totalMs;
  int? get totalMs => _$this._totalMs;
  set totalMs(int? totalMs) => _$this._totalMs = totalMs;

  int? _sessions;
  int? get sessions => _$this._sessions;
  set sessions(int? sessions) => _$this._sessions = sessions;

  int? _distinctItems;
  int? get distinctItems => _$this._distinctItems;
  set distinctItems(int? distinctItems) =>
      _$this._distinctItems = distinctItems;

  int? _newInLibrary;
  int? get newInLibrary => _$this._newInLibrary;
  set newInLibrary(int? newInLibrary) => _$this._newInLibrary = newInLibrary;

  int? _timeSavedMs;
  int? get timeSavedMs => _$this._timeSavedMs;
  set timeSavedMs(int? timeSavedMs) => _$this._timeSavedMs = timeSavedMs;

  int? _longestStreakDays;
  int? get longestStreakDays => _$this._longestStreakDays;
  set longestStreakDays(int? longestStreakDays) =>
      _$this._longestStreakDays = longestStreakDays;

  ListBuilder<MonthListening>? _byMonth;
  ListBuilder<MonthListening> get byMonth =>
      _$this._byMonth ??= ListBuilder<MonthListening>();
  set byMonth(ListBuilder<MonthListening>? byMonth) =>
      _$this._byMonth = byMonth;

  ListBuilder<MediaTypeListening>? _byMediaType;
  ListBuilder<MediaTypeListening> get byMediaType =>
      _$this._byMediaType ??= ListBuilder<MediaTypeListening>();
  set byMediaType(ListBuilder<MediaTypeListening>? byMediaType) =>
      _$this._byMediaType = byMediaType;

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

  ListBuilder<TopEntry>? _topShows;
  ListBuilder<TopEntry> get topShows =>
      _$this._topShows ??= ListBuilder<TopEntry>();
  set topShows(ListBuilder<TopEntry>? topShows) => _$this._topShows = topShows;

  YearInReviewBuilder() {
    YearInReview._defaults(this);
  }

  YearInReviewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _year = $v.year;
      _timezone = $v.timezone;
      _totalMs = $v.totalMs;
      _sessions = $v.sessions;
      _distinctItems = $v.distinctItems;
      _newInLibrary = $v.newInLibrary;
      _timeSavedMs = $v.timeSavedMs;
      _longestStreakDays = $v.longestStreakDays;
      _byMonth = $v.byMonth.toBuilder();
      _byMediaType = $v.byMediaType.toBuilder();
      _topArtists = $v.topArtists.toBuilder();
      _topTracks = $v.topTracks.toBuilder();
      _topGenres = $v.topGenres.toBuilder();
      _topShows = $v.topShows.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(YearInReview other) {
    _$v = other as _$YearInReview;
  }

  @override
  void update(void Function(YearInReviewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  YearInReview build() => _build();

  _$YearInReview _build() {
    _$YearInReview _$result;
    try {
      _$result =
          _$v ??
          _$YearInReview._(
            year: BuiltValueNullFieldError.checkNotNull(
              year,
              r'YearInReview',
              'year',
            ),
            timezone: BuiltValueNullFieldError.checkNotNull(
              timezone,
              r'YearInReview',
              'timezone',
            ),
            totalMs: BuiltValueNullFieldError.checkNotNull(
              totalMs,
              r'YearInReview',
              'totalMs',
            ),
            sessions: BuiltValueNullFieldError.checkNotNull(
              sessions,
              r'YearInReview',
              'sessions',
            ),
            distinctItems: BuiltValueNullFieldError.checkNotNull(
              distinctItems,
              r'YearInReview',
              'distinctItems',
            ),
            newInLibrary: BuiltValueNullFieldError.checkNotNull(
              newInLibrary,
              r'YearInReview',
              'newInLibrary',
            ),
            timeSavedMs: BuiltValueNullFieldError.checkNotNull(
              timeSavedMs,
              r'YearInReview',
              'timeSavedMs',
            ),
            longestStreakDays: BuiltValueNullFieldError.checkNotNull(
              longestStreakDays,
              r'YearInReview',
              'longestStreakDays',
            ),
            byMonth: byMonth.build(),
            byMediaType: byMediaType.build(),
            topArtists: topArtists.build(),
            topTracks: topTracks.build(),
            topGenres: topGenres.build(),
            topShows: topShows.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'byMonth';
        byMonth.build();
        _$failedField = 'byMediaType';
        byMediaType.build();
        _$failedField = 'topArtists';
        topArtists.build();
        _$failedField = 'topTracks';
        topTracks.build();
        _$failedField = 'topGenres';
        topGenres.build();
        _$failedField = 'topShows';
        topShows.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'YearInReview',
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
