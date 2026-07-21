// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'candidate_summary.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CandidateSummary extends CandidateSummary {
  @override
  final String mbid;
  @override
  final String title;
  @override
  final String artist;
  @override
  final int? year;
  @override
  final double similarityPct;

  factory _$CandidateSummary([
    void Function(CandidateSummaryBuilder)? updates,
  ]) => (CandidateSummaryBuilder()..update(updates))._build();

  _$CandidateSummary._({
    required this.mbid,
    required this.title,
    required this.artist,
    this.year,
    required this.similarityPct,
  }) : super._();
  @override
  CandidateSummary rebuild(void Function(CandidateSummaryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CandidateSummaryBuilder toBuilder() =>
      CandidateSummaryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CandidateSummary &&
        mbid == other.mbid &&
        title == other.title &&
        artist == other.artist &&
        year == other.year &&
        similarityPct == other.similarityPct;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, mbid.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, year.hashCode);
    _$hash = $jc(_$hash, similarityPct.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CandidateSummary')
          ..add('mbid', mbid)
          ..add('title', title)
          ..add('artist', artist)
          ..add('year', year)
          ..add('similarityPct', similarityPct))
        .toString();
  }
}

class CandidateSummaryBuilder
    implements Builder<CandidateSummary, CandidateSummaryBuilder> {
  _$CandidateSummary? _$v;

  String? _mbid;
  String? get mbid => _$this._mbid;
  set mbid(String? mbid) => _$this._mbid = mbid;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  int? _year;
  int? get year => _$this._year;
  set year(int? year) => _$this._year = year;

  double? _similarityPct;
  double? get similarityPct => _$this._similarityPct;
  set similarityPct(double? similarityPct) =>
      _$this._similarityPct = similarityPct;

  CandidateSummaryBuilder() {
    CandidateSummary._defaults(this);
  }

  CandidateSummaryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _mbid = $v.mbid;
      _title = $v.title;
      _artist = $v.artist;
      _year = $v.year;
      _similarityPct = $v.similarityPct;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CandidateSummary other) {
    _$v = other as _$CandidateSummary;
  }

  @override
  void update(void Function(CandidateSummaryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CandidateSummary build() => _build();

  _$CandidateSummary _build() {
    final _$result =
        _$v ??
        _$CandidateSummary._(
          mbid: BuiltValueNullFieldError.checkNotNull(
            mbid,
            r'CandidateSummary',
            'mbid',
          ),
          title: BuiltValueNullFieldError.checkNotNull(
            title,
            r'CandidateSummary',
            'title',
          ),
          artist: BuiltValueNullFieldError.checkNotNull(
            artist,
            r'CandidateSummary',
            'artist',
          ),
          year: year,
          similarityPct: BuiltValueNullFieldError.checkNotNull(
            similarityPct,
            r'CandidateSummary',
            'similarityPct',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
