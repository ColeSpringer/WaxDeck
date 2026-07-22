// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'similarity_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SimilarityStatus extends SimilarityStatus {
  @override
  final bool enabled;
  @override
  final String? model;
  @override
  final int? dims;
  @override
  final int embeddedTracks;
  @override
  final int totalTracks;
  @override
  final num coveragePct;
  @override
  final int queueDepth;
  @override
  final DateTime? lastIngestAt;

  factory _$SimilarityStatus([
    void Function(SimilarityStatusBuilder)? updates,
  ]) => (SimilarityStatusBuilder()..update(updates))._build();

  _$SimilarityStatus._({
    required this.enabled,
    this.model,
    this.dims,
    required this.embeddedTracks,
    required this.totalTracks,
    required this.coveragePct,
    required this.queueDepth,
    this.lastIngestAt,
  }) : super._();
  @override
  SimilarityStatus rebuild(void Function(SimilarityStatusBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SimilarityStatusBuilder toBuilder() =>
      SimilarityStatusBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SimilarityStatus &&
        enabled == other.enabled &&
        model == other.model &&
        dims == other.dims &&
        embeddedTracks == other.embeddedTracks &&
        totalTracks == other.totalTracks &&
        coveragePct == other.coveragePct &&
        queueDepth == other.queueDepth &&
        lastIngestAt == other.lastIngestAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, enabled.hashCode);
    _$hash = $jc(_$hash, model.hashCode);
    _$hash = $jc(_$hash, dims.hashCode);
    _$hash = $jc(_$hash, embeddedTracks.hashCode);
    _$hash = $jc(_$hash, totalTracks.hashCode);
    _$hash = $jc(_$hash, coveragePct.hashCode);
    _$hash = $jc(_$hash, queueDepth.hashCode);
    _$hash = $jc(_$hash, lastIngestAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SimilarityStatus')
          ..add('enabled', enabled)
          ..add('model', model)
          ..add('dims', dims)
          ..add('embeddedTracks', embeddedTracks)
          ..add('totalTracks', totalTracks)
          ..add('coveragePct', coveragePct)
          ..add('queueDepth', queueDepth)
          ..add('lastIngestAt', lastIngestAt))
        .toString();
  }
}

class SimilarityStatusBuilder
    implements Builder<SimilarityStatus, SimilarityStatusBuilder> {
  _$SimilarityStatus? _$v;

  bool? _enabled;
  bool? get enabled => _$this._enabled;
  set enabled(bool? enabled) => _$this._enabled = enabled;

  String? _model;
  String? get model => _$this._model;
  set model(String? model) => _$this._model = model;

  int? _dims;
  int? get dims => _$this._dims;
  set dims(int? dims) => _$this._dims = dims;

  int? _embeddedTracks;
  int? get embeddedTracks => _$this._embeddedTracks;
  set embeddedTracks(int? embeddedTracks) =>
      _$this._embeddedTracks = embeddedTracks;

  int? _totalTracks;
  int? get totalTracks => _$this._totalTracks;
  set totalTracks(int? totalTracks) => _$this._totalTracks = totalTracks;

  num? _coveragePct;
  num? get coveragePct => _$this._coveragePct;
  set coveragePct(num? coveragePct) => _$this._coveragePct = coveragePct;

  int? _queueDepth;
  int? get queueDepth => _$this._queueDepth;
  set queueDepth(int? queueDepth) => _$this._queueDepth = queueDepth;

  DateTime? _lastIngestAt;
  DateTime? get lastIngestAt => _$this._lastIngestAt;
  set lastIngestAt(DateTime? lastIngestAt) =>
      _$this._lastIngestAt = lastIngestAt;

  SimilarityStatusBuilder() {
    SimilarityStatus._defaults(this);
  }

  SimilarityStatusBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _enabled = $v.enabled;
      _model = $v.model;
      _dims = $v.dims;
      _embeddedTracks = $v.embeddedTracks;
      _totalTracks = $v.totalTracks;
      _coveragePct = $v.coveragePct;
      _queueDepth = $v.queueDepth;
      _lastIngestAt = $v.lastIngestAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SimilarityStatus other) {
    _$v = other as _$SimilarityStatus;
  }

  @override
  void update(void Function(SimilarityStatusBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SimilarityStatus build() => _build();

  _$SimilarityStatus _build() {
    final _$result =
        _$v ??
        _$SimilarityStatus._(
          enabled: BuiltValueNullFieldError.checkNotNull(
            enabled,
            r'SimilarityStatus',
            'enabled',
          ),
          model: model,
          dims: dims,
          embeddedTracks: BuiltValueNullFieldError.checkNotNull(
            embeddedTracks,
            r'SimilarityStatus',
            'embeddedTracks',
          ),
          totalTracks: BuiltValueNullFieldError.checkNotNull(
            totalTracks,
            r'SimilarityStatus',
            'totalTracks',
          ),
          coveragePct: BuiltValueNullFieldError.checkNotNull(
            coveragePct,
            r'SimilarityStatus',
            'coveragePct',
          ),
          queueDepth: BuiltValueNullFieldError.checkNotNull(
            queueDepth,
            r'SimilarityStatus',
            'queueDepth',
          ),
          lastIngestAt: lastIngestAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
