// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'played_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlayedUpdate extends PlayedUpdate {
  @override
  final bool played;
  @override
  final bool finished;
  @override
  final int? playCount;
  @override
  final int? positionMs;
  @override
  final DateTime? recordedAt;

  factory _$PlayedUpdate([void Function(PlayedUpdateBuilder)? updates]) =>
      (PlayedUpdateBuilder()..update(updates))._build();

  _$PlayedUpdate._({
    required this.played,
    required this.finished,
    this.playCount,
    this.positionMs,
    this.recordedAt,
  }) : super._();
  @override
  PlayedUpdate rebuild(void Function(PlayedUpdateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlayedUpdateBuilder toBuilder() => PlayedUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlayedUpdate &&
        played == other.played &&
        finished == other.finished &&
        playCount == other.playCount &&
        positionMs == other.positionMs &&
        recordedAt == other.recordedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, played.hashCode);
    _$hash = $jc(_$hash, finished.hashCode);
    _$hash = $jc(_$hash, playCount.hashCode);
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jc(_$hash, recordedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlayedUpdate')
          ..add('played', played)
          ..add('finished', finished)
          ..add('playCount', playCount)
          ..add('positionMs', positionMs)
          ..add('recordedAt', recordedAt))
        .toString();
  }
}

class PlayedUpdateBuilder
    implements Builder<PlayedUpdate, PlayedUpdateBuilder> {
  _$PlayedUpdate? _$v;

  bool? _played;
  bool? get played => _$this._played;
  set played(bool? played) => _$this._played = played;

  bool? _finished;
  bool? get finished => _$this._finished;
  set finished(bool? finished) => _$this._finished = finished;

  int? _playCount;
  int? get playCount => _$this._playCount;
  set playCount(int? playCount) => _$this._playCount = playCount;

  int? _positionMs;
  int? get positionMs => _$this._positionMs;
  set positionMs(int? positionMs) => _$this._positionMs = positionMs;

  DateTime? _recordedAt;
  DateTime? get recordedAt => _$this._recordedAt;
  set recordedAt(DateTime? recordedAt) => _$this._recordedAt = recordedAt;

  PlayedUpdateBuilder() {
    PlayedUpdate._defaults(this);
  }

  PlayedUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _played = $v.played;
      _finished = $v.finished;
      _playCount = $v.playCount;
      _positionMs = $v.positionMs;
      _recordedAt = $v.recordedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlayedUpdate other) {
    _$v = other as _$PlayedUpdate;
  }

  @override
  void update(void Function(PlayedUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlayedUpdate build() => _build();

  _$PlayedUpdate _build() {
    final _$result =
        _$v ??
        _$PlayedUpdate._(
          played: BuiltValueNullFieldError.checkNotNull(
            played,
            r'PlayedUpdate',
            'played',
          ),
          finished: BuiltValueNullFieldError.checkNotNull(
            finished,
            r'PlayedUpdate',
            'finished',
          ),
          playCount: playCount,
          positionMs: positionMs,
          recordedAt: recordedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
