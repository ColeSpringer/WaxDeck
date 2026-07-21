// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_entry_detail.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReviewEntryDetail extends ReviewEntryDetail {
  @override
  final BuiltList<ReviewCandidate> candidates;
  @override
  final BuiltList<ReviewTrack> tracks;
  @override
  final String id;
  @override
  final String kind;
  @override
  final String status;
  @override
  final MediaType mediaType;
  @override
  final String origin;
  @override
  final String? title;
  @override
  final String? artist;
  @override
  final int trackCount;
  @override
  final String? libraryPid;
  @override
  final String? uploadedBy;
  @override
  final bool identifying;
  @override
  final CandidateSummary? best;
  @override
  final String? appliedMbid;
  @override
  final DateTime createdAt;
  @override
  final DateTime? decidedAt;
  @override
  final String? decidedBy;

  factory _$ReviewEntryDetail([
    void Function(ReviewEntryDetailBuilder)? updates,
  ]) => (ReviewEntryDetailBuilder()..update(updates))._build();

  _$ReviewEntryDetail._({
    required this.candidates,
    required this.tracks,
    required this.id,
    required this.kind,
    required this.status,
    required this.mediaType,
    required this.origin,
    this.title,
    this.artist,
    required this.trackCount,
    this.libraryPid,
    this.uploadedBy,
    required this.identifying,
    this.best,
    this.appliedMbid,
    required this.createdAt,
    this.decidedAt,
    this.decidedBy,
  }) : super._();
  @override
  ReviewEntryDetail rebuild(void Function(ReviewEntryDetailBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReviewEntryDetailBuilder toBuilder() =>
      ReviewEntryDetailBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewEntryDetail &&
        candidates == other.candidates &&
        tracks == other.tracks &&
        id == other.id &&
        kind == other.kind &&
        status == other.status &&
        mediaType == other.mediaType &&
        origin == other.origin &&
        title == other.title &&
        artist == other.artist &&
        trackCount == other.trackCount &&
        libraryPid == other.libraryPid &&
        uploadedBy == other.uploadedBy &&
        identifying == other.identifying &&
        best == other.best &&
        appliedMbid == other.appliedMbid &&
        createdAt == other.createdAt &&
        decidedAt == other.decidedAt &&
        decidedBy == other.decidedBy;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, candidates.hashCode);
    _$hash = $jc(_$hash, tracks.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, origin.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, trackCount.hashCode);
    _$hash = $jc(_$hash, libraryPid.hashCode);
    _$hash = $jc(_$hash, uploadedBy.hashCode);
    _$hash = $jc(_$hash, identifying.hashCode);
    _$hash = $jc(_$hash, best.hashCode);
    _$hash = $jc(_$hash, appliedMbid.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, decidedAt.hashCode);
    _$hash = $jc(_$hash, decidedBy.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewEntryDetail')
          ..add('candidates', candidates)
          ..add('tracks', tracks)
          ..add('id', id)
          ..add('kind', kind)
          ..add('status', status)
          ..add('mediaType', mediaType)
          ..add('origin', origin)
          ..add('title', title)
          ..add('artist', artist)
          ..add('trackCount', trackCount)
          ..add('libraryPid', libraryPid)
          ..add('uploadedBy', uploadedBy)
          ..add('identifying', identifying)
          ..add('best', best)
          ..add('appliedMbid', appliedMbid)
          ..add('createdAt', createdAt)
          ..add('decidedAt', decidedAt)
          ..add('decidedBy', decidedBy))
        .toString();
  }
}

class ReviewEntryDetailBuilder
    implements
        Builder<ReviewEntryDetail, ReviewEntryDetailBuilder>,
        ReviewEntryBuilder {
  _$ReviewEntryDetail? _$v;

  ListBuilder<ReviewCandidate>? _candidates;
  ListBuilder<ReviewCandidate> get candidates =>
      _$this._candidates ??= ListBuilder<ReviewCandidate>();
  set candidates(covariant ListBuilder<ReviewCandidate>? candidates) =>
      _$this._candidates = candidates;

  ListBuilder<ReviewTrack>? _tracks;
  ListBuilder<ReviewTrack> get tracks =>
      _$this._tracks ??= ListBuilder<ReviewTrack>();
  set tracks(covariant ListBuilder<ReviewTrack>? tracks) =>
      _$this._tracks = tracks;

  String? _id;
  String? get id => _$this._id;
  set id(covariant String? id) => _$this._id = id;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(covariant String? kind) => _$this._kind = kind;

  String? _status;
  String? get status => _$this._status;
  set status(covariant String? status) => _$this._status = status;

  MediaType? _mediaType;
  MediaType? get mediaType => _$this._mediaType;
  set mediaType(covariant MediaType? mediaType) =>
      _$this._mediaType = mediaType;

  String? _origin;
  String? get origin => _$this._origin;
  set origin(covariant String? origin) => _$this._origin = origin;

  String? _title;
  String? get title => _$this._title;
  set title(covariant String? title) => _$this._title = title;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(covariant String? artist) => _$this._artist = artist;

  int? _trackCount;
  int? get trackCount => _$this._trackCount;
  set trackCount(covariant int? trackCount) => _$this._trackCount = trackCount;

  String? _libraryPid;
  String? get libraryPid => _$this._libraryPid;
  set libraryPid(covariant String? libraryPid) =>
      _$this._libraryPid = libraryPid;

  String? _uploadedBy;
  String? get uploadedBy => _$this._uploadedBy;
  set uploadedBy(covariant String? uploadedBy) =>
      _$this._uploadedBy = uploadedBy;

  bool? _identifying;
  bool? get identifying => _$this._identifying;
  set identifying(covariant bool? identifying) =>
      _$this._identifying = identifying;

  CandidateSummaryBuilder? _best;
  CandidateSummaryBuilder get best =>
      _$this._best ??= CandidateSummaryBuilder();
  set best(covariant CandidateSummaryBuilder? best) => _$this._best = best;

  String? _appliedMbid;
  String? get appliedMbid => _$this._appliedMbid;
  set appliedMbid(covariant String? appliedMbid) =>
      _$this._appliedMbid = appliedMbid;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(covariant DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _decidedAt;
  DateTime? get decidedAt => _$this._decidedAt;
  set decidedAt(covariant DateTime? decidedAt) => _$this._decidedAt = decidedAt;

  String? _decidedBy;
  String? get decidedBy => _$this._decidedBy;
  set decidedBy(covariant String? decidedBy) => _$this._decidedBy = decidedBy;

  ReviewEntryDetailBuilder() {
    ReviewEntryDetail._defaults(this);
  }

  ReviewEntryDetailBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _candidates = $v.candidates.toBuilder();
      _tracks = $v.tracks.toBuilder();
      _id = $v.id;
      _kind = $v.kind;
      _status = $v.status;
      _mediaType = $v.mediaType;
      _origin = $v.origin;
      _title = $v.title;
      _artist = $v.artist;
      _trackCount = $v.trackCount;
      _libraryPid = $v.libraryPid;
      _uploadedBy = $v.uploadedBy;
      _identifying = $v.identifying;
      _best = $v.best?.toBuilder();
      _appliedMbid = $v.appliedMbid;
      _createdAt = $v.createdAt;
      _decidedAt = $v.decidedAt;
      _decidedBy = $v.decidedBy;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant ReviewEntryDetail other) {
    _$v = other as _$ReviewEntryDetail;
  }

  @override
  void update(void Function(ReviewEntryDetailBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewEntryDetail build() => _build();

  _$ReviewEntryDetail _build() {
    _$ReviewEntryDetail _$result;
    try {
      _$result =
          _$v ??
          _$ReviewEntryDetail._(
            candidates: candidates.build(),
            tracks: tracks.build(),
            id: BuiltValueNullFieldError.checkNotNull(
              id,
              r'ReviewEntryDetail',
              'id',
            ),
            kind: BuiltValueNullFieldError.checkNotNull(
              kind,
              r'ReviewEntryDetail',
              'kind',
            ),
            status: BuiltValueNullFieldError.checkNotNull(
              status,
              r'ReviewEntryDetail',
              'status',
            ),
            mediaType: BuiltValueNullFieldError.checkNotNull(
              mediaType,
              r'ReviewEntryDetail',
              'mediaType',
            ),
            origin: BuiltValueNullFieldError.checkNotNull(
              origin,
              r'ReviewEntryDetail',
              'origin',
            ),
            title: title,
            artist: artist,
            trackCount: BuiltValueNullFieldError.checkNotNull(
              trackCount,
              r'ReviewEntryDetail',
              'trackCount',
            ),
            libraryPid: libraryPid,
            uploadedBy: uploadedBy,
            identifying: BuiltValueNullFieldError.checkNotNull(
              identifying,
              r'ReviewEntryDetail',
              'identifying',
            ),
            best: _best?.build(),
            appliedMbid: appliedMbid,
            createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt,
              r'ReviewEntryDetail',
              'createdAt',
            ),
            decidedAt: decidedAt,
            decidedBy: decidedBy,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'candidates';
        candidates.build();
        _$failedField = 'tracks';
        tracks.build();

        _$failedField = 'best';
        _best?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ReviewEntryDetail',
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
