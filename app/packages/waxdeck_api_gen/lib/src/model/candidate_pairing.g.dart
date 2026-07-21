// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'candidate_pairing.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CandidatePairing extends CandidatePairing {
  @override
  final int trackIndex;
  @override
  final int position;
  @override
  final int? disc;
  @override
  final String title;
  @override
  final String? artist;
  @override
  final int? durationMs;
  @override
  final String? recordingMbid;
  @override
  final double distance;

  factory _$CandidatePairing([
    void Function(CandidatePairingBuilder)? updates,
  ]) => (CandidatePairingBuilder()..update(updates))._build();

  _$CandidatePairing._({
    required this.trackIndex,
    required this.position,
    this.disc,
    required this.title,
    this.artist,
    this.durationMs,
    this.recordingMbid,
    required this.distance,
  }) : super._();
  @override
  CandidatePairing rebuild(void Function(CandidatePairingBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CandidatePairingBuilder toBuilder() =>
      CandidatePairingBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CandidatePairing &&
        trackIndex == other.trackIndex &&
        position == other.position &&
        disc == other.disc &&
        title == other.title &&
        artist == other.artist &&
        durationMs == other.durationMs &&
        recordingMbid == other.recordingMbid &&
        distance == other.distance;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, trackIndex.hashCode);
    _$hash = $jc(_$hash, position.hashCode);
    _$hash = $jc(_$hash, disc.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jc(_$hash, recordingMbid.hashCode);
    _$hash = $jc(_$hash, distance.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CandidatePairing')
          ..add('trackIndex', trackIndex)
          ..add('position', position)
          ..add('disc', disc)
          ..add('title', title)
          ..add('artist', artist)
          ..add('durationMs', durationMs)
          ..add('recordingMbid', recordingMbid)
          ..add('distance', distance))
        .toString();
  }
}

class CandidatePairingBuilder
    implements Builder<CandidatePairing, CandidatePairingBuilder> {
  _$CandidatePairing? _$v;

  int? _trackIndex;
  int? get trackIndex => _$this._trackIndex;
  set trackIndex(int? trackIndex) => _$this._trackIndex = trackIndex;

  int? _position;
  int? get position => _$this._position;
  set position(int? position) => _$this._position = position;

  int? _disc;
  int? get disc => _$this._disc;
  set disc(int? disc) => _$this._disc = disc;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  String? _recordingMbid;
  String? get recordingMbid => _$this._recordingMbid;
  set recordingMbid(String? recordingMbid) =>
      _$this._recordingMbid = recordingMbid;

  double? _distance;
  double? get distance => _$this._distance;
  set distance(double? distance) => _$this._distance = distance;

  CandidatePairingBuilder() {
    CandidatePairing._defaults(this);
  }

  CandidatePairingBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _trackIndex = $v.trackIndex;
      _position = $v.position;
      _disc = $v.disc;
      _title = $v.title;
      _artist = $v.artist;
      _durationMs = $v.durationMs;
      _recordingMbid = $v.recordingMbid;
      _distance = $v.distance;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CandidatePairing other) {
    _$v = other as _$CandidatePairing;
  }

  @override
  void update(void Function(CandidatePairingBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CandidatePairing build() => _build();

  _$CandidatePairing _build() {
    final _$result =
        _$v ??
        _$CandidatePairing._(
          trackIndex: BuiltValueNullFieldError.checkNotNull(
            trackIndex,
            r'CandidatePairing',
            'trackIndex',
          ),
          position: BuiltValueNullFieldError.checkNotNull(
            position,
            r'CandidatePairing',
            'position',
          ),
          disc: disc,
          title: BuiltValueNullFieldError.checkNotNull(
            title,
            r'CandidatePairing',
            'title',
          ),
          artist: artist,
          durationMs: durationMs,
          recordingMbid: recordingMbid,
          distance: BuiltValueNullFieldError.checkNotNull(
            distance,
            r'CandidatePairing',
            'distance',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
