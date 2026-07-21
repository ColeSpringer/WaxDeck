// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_candidate.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReviewCandidate extends ReviewCandidate {
  @override
  final String mbid;
  @override
  final String? releaseGroupMbid;
  @override
  final String title;
  @override
  final String artist;
  @override
  final int? year;
  @override
  final int? mediaCount;
  @override
  final int? trackCount;
  @override
  final String? country;
  @override
  final String? label;
  @override
  final String? catalogNumber;
  @override
  final bool? compilation;
  @override
  final double similarityPct;
  @override
  final BuiltList<CandidateComponent>? components;
  @override
  final BuiltList<CandidatePairing> pairings;
  @override
  final BuiltList<String>? missingTitles;
  @override
  final BuiltList<int>? extraTrackIndexes;

  factory _$ReviewCandidate([void Function(ReviewCandidateBuilder)? updates]) =>
      (ReviewCandidateBuilder()..update(updates))._build();

  _$ReviewCandidate._({
    required this.mbid,
    this.releaseGroupMbid,
    required this.title,
    required this.artist,
    this.year,
    this.mediaCount,
    this.trackCount,
    this.country,
    this.label,
    this.catalogNumber,
    this.compilation,
    required this.similarityPct,
    this.components,
    required this.pairings,
    this.missingTitles,
    this.extraTrackIndexes,
  }) : super._();
  @override
  ReviewCandidate rebuild(void Function(ReviewCandidateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReviewCandidateBuilder toBuilder() => ReviewCandidateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewCandidate &&
        mbid == other.mbid &&
        releaseGroupMbid == other.releaseGroupMbid &&
        title == other.title &&
        artist == other.artist &&
        year == other.year &&
        mediaCount == other.mediaCount &&
        trackCount == other.trackCount &&
        country == other.country &&
        label == other.label &&
        catalogNumber == other.catalogNumber &&
        compilation == other.compilation &&
        similarityPct == other.similarityPct &&
        components == other.components &&
        pairings == other.pairings &&
        missingTitles == other.missingTitles &&
        extraTrackIndexes == other.extraTrackIndexes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, mbid.hashCode);
    _$hash = $jc(_$hash, releaseGroupMbid.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, year.hashCode);
    _$hash = $jc(_$hash, mediaCount.hashCode);
    _$hash = $jc(_$hash, trackCount.hashCode);
    _$hash = $jc(_$hash, country.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, catalogNumber.hashCode);
    _$hash = $jc(_$hash, compilation.hashCode);
    _$hash = $jc(_$hash, similarityPct.hashCode);
    _$hash = $jc(_$hash, components.hashCode);
    _$hash = $jc(_$hash, pairings.hashCode);
    _$hash = $jc(_$hash, missingTitles.hashCode);
    _$hash = $jc(_$hash, extraTrackIndexes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewCandidate')
          ..add('mbid', mbid)
          ..add('releaseGroupMbid', releaseGroupMbid)
          ..add('title', title)
          ..add('artist', artist)
          ..add('year', year)
          ..add('mediaCount', mediaCount)
          ..add('trackCount', trackCount)
          ..add('country', country)
          ..add('label', label)
          ..add('catalogNumber', catalogNumber)
          ..add('compilation', compilation)
          ..add('similarityPct', similarityPct)
          ..add('components', components)
          ..add('pairings', pairings)
          ..add('missingTitles', missingTitles)
          ..add('extraTrackIndexes', extraTrackIndexes))
        .toString();
  }
}

class ReviewCandidateBuilder
    implements Builder<ReviewCandidate, ReviewCandidateBuilder> {
  _$ReviewCandidate? _$v;

  String? _mbid;
  String? get mbid => _$this._mbid;
  set mbid(String? mbid) => _$this._mbid = mbid;

  String? _releaseGroupMbid;
  String? get releaseGroupMbid => _$this._releaseGroupMbid;
  set releaseGroupMbid(String? releaseGroupMbid) =>
      _$this._releaseGroupMbid = releaseGroupMbid;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  int? _year;
  int? get year => _$this._year;
  set year(int? year) => _$this._year = year;

  int? _mediaCount;
  int? get mediaCount => _$this._mediaCount;
  set mediaCount(int? mediaCount) => _$this._mediaCount = mediaCount;

  int? _trackCount;
  int? get trackCount => _$this._trackCount;
  set trackCount(int? trackCount) => _$this._trackCount = trackCount;

  String? _country;
  String? get country => _$this._country;
  set country(String? country) => _$this._country = country;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  String? _catalogNumber;
  String? get catalogNumber => _$this._catalogNumber;
  set catalogNumber(String? catalogNumber) =>
      _$this._catalogNumber = catalogNumber;

  bool? _compilation;
  bool? get compilation => _$this._compilation;
  set compilation(bool? compilation) => _$this._compilation = compilation;

  double? _similarityPct;
  double? get similarityPct => _$this._similarityPct;
  set similarityPct(double? similarityPct) =>
      _$this._similarityPct = similarityPct;

  ListBuilder<CandidateComponent>? _components;
  ListBuilder<CandidateComponent> get components =>
      _$this._components ??= ListBuilder<CandidateComponent>();
  set components(ListBuilder<CandidateComponent>? components) =>
      _$this._components = components;

  ListBuilder<CandidatePairing>? _pairings;
  ListBuilder<CandidatePairing> get pairings =>
      _$this._pairings ??= ListBuilder<CandidatePairing>();
  set pairings(ListBuilder<CandidatePairing>? pairings) =>
      _$this._pairings = pairings;

  ListBuilder<String>? _missingTitles;
  ListBuilder<String> get missingTitles =>
      _$this._missingTitles ??= ListBuilder<String>();
  set missingTitles(ListBuilder<String>? missingTitles) =>
      _$this._missingTitles = missingTitles;

  ListBuilder<int>? _extraTrackIndexes;
  ListBuilder<int> get extraTrackIndexes =>
      _$this._extraTrackIndexes ??= ListBuilder<int>();
  set extraTrackIndexes(ListBuilder<int>? extraTrackIndexes) =>
      _$this._extraTrackIndexes = extraTrackIndexes;

  ReviewCandidateBuilder() {
    ReviewCandidate._defaults(this);
  }

  ReviewCandidateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _mbid = $v.mbid;
      _releaseGroupMbid = $v.releaseGroupMbid;
      _title = $v.title;
      _artist = $v.artist;
      _year = $v.year;
      _mediaCount = $v.mediaCount;
      _trackCount = $v.trackCount;
      _country = $v.country;
      _label = $v.label;
      _catalogNumber = $v.catalogNumber;
      _compilation = $v.compilation;
      _similarityPct = $v.similarityPct;
      _components = $v.components?.toBuilder();
      _pairings = $v.pairings.toBuilder();
      _missingTitles = $v.missingTitles?.toBuilder();
      _extraTrackIndexes = $v.extraTrackIndexes?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewCandidate other) {
    _$v = other as _$ReviewCandidate;
  }

  @override
  void update(void Function(ReviewCandidateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewCandidate build() => _build();

  _$ReviewCandidate _build() {
    _$ReviewCandidate _$result;
    try {
      _$result =
          _$v ??
          _$ReviewCandidate._(
            mbid: BuiltValueNullFieldError.checkNotNull(
              mbid,
              r'ReviewCandidate',
              'mbid',
            ),
            releaseGroupMbid: releaseGroupMbid,
            title: BuiltValueNullFieldError.checkNotNull(
              title,
              r'ReviewCandidate',
              'title',
            ),
            artist: BuiltValueNullFieldError.checkNotNull(
              artist,
              r'ReviewCandidate',
              'artist',
            ),
            year: year,
            mediaCount: mediaCount,
            trackCount: trackCount,
            country: country,
            label: label,
            catalogNumber: catalogNumber,
            compilation: compilation,
            similarityPct: BuiltValueNullFieldError.checkNotNull(
              similarityPct,
              r'ReviewCandidate',
              'similarityPct',
            ),
            components: _components?.build(),
            pairings: pairings.build(),
            missingTitles: _missingTitles?.build(),
            extraTrackIndexes: _extraTrackIndexes?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'components';
        _components?.build();
        _$failedField = 'pairings';
        pairings.build();
        _$failedField = 'missingTitles';
        _missingTitles?.build();
        _$failedField = 'extraTrackIndexes';
        _extraTrackIndexes?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ReviewCandidate',
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
