// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_track.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ReviewTrack extends ReviewTrack {
  @override
  final String? pid;
  @override
  final String path;
  @override
  final String title;
  @override
  final String? artist;
  @override
  final int? trackNo;
  @override
  final int? discNo;
  @override
  final int durationMs;

  factory _$ReviewTrack([void Function(ReviewTrackBuilder)? updates]) =>
      (ReviewTrackBuilder()..update(updates))._build();

  _$ReviewTrack._({
    this.pid,
    required this.path,
    required this.title,
    this.artist,
    this.trackNo,
    this.discNo,
    required this.durationMs,
  }) : super._();
  @override
  ReviewTrack rebuild(void Function(ReviewTrackBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReviewTrackBuilder toBuilder() => ReviewTrackBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReviewTrack &&
        pid == other.pid &&
        path == other.path &&
        title == other.title &&
        artist == other.artist &&
        trackNo == other.trackNo &&
        discNo == other.discNo &&
        durationMs == other.durationMs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, trackNo.hashCode);
    _$hash = $jc(_$hash, discNo.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReviewTrack')
          ..add('pid', pid)
          ..add('path', path)
          ..add('title', title)
          ..add('artist', artist)
          ..add('trackNo', trackNo)
          ..add('discNo', discNo)
          ..add('durationMs', durationMs))
        .toString();
  }
}

class ReviewTrackBuilder implements Builder<ReviewTrack, ReviewTrackBuilder> {
  _$ReviewTrack? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  int? _trackNo;
  int? get trackNo => _$this._trackNo;
  set trackNo(int? trackNo) => _$this._trackNo = trackNo;

  int? _discNo;
  int? get discNo => _$this._discNo;
  set discNo(int? discNo) => _$this._discNo = discNo;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  ReviewTrackBuilder() {
    ReviewTrack._defaults(this);
  }

  ReviewTrackBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _path = $v.path;
      _title = $v.title;
      _artist = $v.artist;
      _trackNo = $v.trackNo;
      _discNo = $v.discNo;
      _durationMs = $v.durationMs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReviewTrack other) {
    _$v = other as _$ReviewTrack;
  }

  @override
  void update(void Function(ReviewTrackBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReviewTrack build() => _build();

  _$ReviewTrack _build() {
    final _$result =
        _$v ??
        _$ReviewTrack._(
          pid: pid,
          path: BuiltValueNullFieldError.checkNotNull(
            path,
            r'ReviewTrack',
            'path',
          ),
          title: BuiltValueNullFieldError.checkNotNull(
            title,
            r'ReviewTrack',
            'title',
          ),
          artist: artist,
          trackNo: trackNo,
          discNo: discNo,
          durationMs: BuiltValueNullFieldError.checkNotNull(
            durationMs,
            r'ReviewTrack',
            'durationMs',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
