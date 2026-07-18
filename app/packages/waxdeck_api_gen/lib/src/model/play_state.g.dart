// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'play_state.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlayState extends PlayState {
  @override
  final String pid;
  @override
  final int positionMs;
  @override
  final bool played;
  @override
  final bool finished;
  @override
  final int playCount;
  @override
  final bool starred;
  @override
  final int? rating;
  @override
  final DateTime? updatedAt;

  factory _$PlayState([void Function(PlayStateBuilder)? updates]) =>
      (PlayStateBuilder()..update(updates))._build();

  _$PlayState._({
    required this.pid,
    required this.positionMs,
    required this.played,
    required this.finished,
    required this.playCount,
    required this.starred,
    this.rating,
    this.updatedAt,
  }) : super._();
  @override
  PlayState rebuild(void Function(PlayStateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlayStateBuilder toBuilder() => PlayStateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlayState &&
        pid == other.pid &&
        positionMs == other.positionMs &&
        played == other.played &&
        finished == other.finished &&
        playCount == other.playCount &&
        starred == other.starred &&
        rating == other.rating &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jc(_$hash, played.hashCode);
    _$hash = $jc(_$hash, finished.hashCode);
    _$hash = $jc(_$hash, playCount.hashCode);
    _$hash = $jc(_$hash, starred.hashCode);
    _$hash = $jc(_$hash, rating.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlayState')
          ..add('pid', pid)
          ..add('positionMs', positionMs)
          ..add('played', played)
          ..add('finished', finished)
          ..add('playCount', playCount)
          ..add('starred', starred)
          ..add('rating', rating)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class PlayStateBuilder implements Builder<PlayState, PlayStateBuilder> {
  _$PlayState? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  int? _positionMs;
  int? get positionMs => _$this._positionMs;
  set positionMs(int? positionMs) => _$this._positionMs = positionMs;

  bool? _played;
  bool? get played => _$this._played;
  set played(bool? played) => _$this._played = played;

  bool? _finished;
  bool? get finished => _$this._finished;
  set finished(bool? finished) => _$this._finished = finished;

  int? _playCount;
  int? get playCount => _$this._playCount;
  set playCount(int? playCount) => _$this._playCount = playCount;

  bool? _starred;
  bool? get starred => _$this._starred;
  set starred(bool? starred) => _$this._starred = starred;

  int? _rating;
  int? get rating => _$this._rating;
  set rating(int? rating) => _$this._rating = rating;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  PlayStateBuilder() {
    PlayState._defaults(this);
  }

  PlayStateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _positionMs = $v.positionMs;
      _played = $v.played;
      _finished = $v.finished;
      _playCount = $v.playCount;
      _starred = $v.starred;
      _rating = $v.rating;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlayState other) {
    _$v = other as _$PlayState;
  }

  @override
  void update(void Function(PlayStateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlayState build() => _build();

  _$PlayState _build() {
    final _$result =
        _$v ??
        _$PlayState._(
          pid: BuiltValueNullFieldError.checkNotNull(pid, r'PlayState', 'pid'),
          positionMs: BuiltValueNullFieldError.checkNotNull(
            positionMs,
            r'PlayState',
            'positionMs',
          ),
          played: BuiltValueNullFieldError.checkNotNull(
            played,
            r'PlayState',
            'played',
          ),
          finished: BuiltValueNullFieldError.checkNotNull(
            finished,
            r'PlayState',
            'finished',
          ),
          playCount: BuiltValueNullFieldError.checkNotNull(
            playCount,
            r'PlayState',
            'playCount',
          ),
          starred: BuiltValueNullFieldError.checkNotNull(
            starred,
            r'PlayState',
            'starred',
          ),
          rating: rating,
          updatedAt: updatedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
