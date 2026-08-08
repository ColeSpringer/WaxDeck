// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radio_saved_song_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RadioSavedSongCreate extends RadioSavedSongCreate {
  @override
  final String stationPid;
  @override
  final String nowPlaying;

  factory _$RadioSavedSongCreate([
    void Function(RadioSavedSongCreateBuilder)? updates,
  ]) => (RadioSavedSongCreateBuilder()..update(updates))._build();

  _$RadioSavedSongCreate._({required this.stationPid, required this.nowPlaying})
    : super._();
  @override
  RadioSavedSongCreate rebuild(
    void Function(RadioSavedSongCreateBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  RadioSavedSongCreateBuilder toBuilder() =>
      RadioSavedSongCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RadioSavedSongCreate &&
        stationPid == other.stationPid &&
        nowPlaying == other.nowPlaying;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, stationPid.hashCode);
    _$hash = $jc(_$hash, nowPlaying.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RadioSavedSongCreate')
          ..add('stationPid', stationPid)
          ..add('nowPlaying', nowPlaying))
        .toString();
  }
}

class RadioSavedSongCreateBuilder
    implements Builder<RadioSavedSongCreate, RadioSavedSongCreateBuilder> {
  _$RadioSavedSongCreate? _$v;

  String? _stationPid;
  String? get stationPid => _$this._stationPid;
  set stationPid(String? stationPid) => _$this._stationPid = stationPid;

  String? _nowPlaying;
  String? get nowPlaying => _$this._nowPlaying;
  set nowPlaying(String? nowPlaying) => _$this._nowPlaying = nowPlaying;

  RadioSavedSongCreateBuilder() {
    RadioSavedSongCreate._defaults(this);
  }

  RadioSavedSongCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _stationPid = $v.stationPid;
      _nowPlaying = $v.nowPlaying;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RadioSavedSongCreate other) {
    _$v = other as _$RadioSavedSongCreate;
  }

  @override
  void update(void Function(RadioSavedSongCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RadioSavedSongCreate build() => _build();

  _$RadioSavedSongCreate _build() {
    final _$result =
        _$v ??
        _$RadioSavedSongCreate._(
          stationPid: BuiltValueNullFieldError.checkNotNull(
            stationPid,
            r'RadioSavedSongCreate',
            'stationPid',
          ),
          nowPlaying: BuiltValueNullFieldError.checkNotNull(
            nowPlaying,
            r'RadioSavedSongCreate',
            'nowPlaying',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
