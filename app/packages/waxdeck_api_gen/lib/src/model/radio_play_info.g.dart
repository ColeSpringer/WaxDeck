// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radio_play_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RadioPlayInfo extends RadioPlayInfo {
  @override
  final String url;
  @override
  final String? nowPlaying;
  @override
  final String? nowPlayingItemPid;
  @override
  final String? nowPlayingArtKey;
  @override
  final bool? nowPlayingSaved;
  @override
  final String? nowPlayingSavedPid;

  factory _$RadioPlayInfo([void Function(RadioPlayInfoBuilder)? updates]) =>
      (RadioPlayInfoBuilder()..update(updates))._build();

  _$RadioPlayInfo._({
    required this.url,
    this.nowPlaying,
    this.nowPlayingItemPid,
    this.nowPlayingArtKey,
    this.nowPlayingSaved,
    this.nowPlayingSavedPid,
  }) : super._();
  @override
  RadioPlayInfo rebuild(void Function(RadioPlayInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RadioPlayInfoBuilder toBuilder() => RadioPlayInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RadioPlayInfo &&
        url == other.url &&
        nowPlaying == other.nowPlaying &&
        nowPlayingItemPid == other.nowPlayingItemPid &&
        nowPlayingArtKey == other.nowPlayingArtKey &&
        nowPlayingSaved == other.nowPlayingSaved &&
        nowPlayingSavedPid == other.nowPlayingSavedPid;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, nowPlaying.hashCode);
    _$hash = $jc(_$hash, nowPlayingItemPid.hashCode);
    _$hash = $jc(_$hash, nowPlayingArtKey.hashCode);
    _$hash = $jc(_$hash, nowPlayingSaved.hashCode);
    _$hash = $jc(_$hash, nowPlayingSavedPid.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RadioPlayInfo')
          ..add('url', url)
          ..add('nowPlaying', nowPlaying)
          ..add('nowPlayingItemPid', nowPlayingItemPid)
          ..add('nowPlayingArtKey', nowPlayingArtKey)
          ..add('nowPlayingSaved', nowPlayingSaved)
          ..add('nowPlayingSavedPid', nowPlayingSavedPid))
        .toString();
  }
}

class RadioPlayInfoBuilder
    implements Builder<RadioPlayInfo, RadioPlayInfoBuilder> {
  _$RadioPlayInfo? _$v;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _nowPlaying;
  String? get nowPlaying => _$this._nowPlaying;
  set nowPlaying(String? nowPlaying) => _$this._nowPlaying = nowPlaying;

  String? _nowPlayingItemPid;
  String? get nowPlayingItemPid => _$this._nowPlayingItemPid;
  set nowPlayingItemPid(String? nowPlayingItemPid) =>
      _$this._nowPlayingItemPid = nowPlayingItemPid;

  String? _nowPlayingArtKey;
  String? get nowPlayingArtKey => _$this._nowPlayingArtKey;
  set nowPlayingArtKey(String? nowPlayingArtKey) =>
      _$this._nowPlayingArtKey = nowPlayingArtKey;

  bool? _nowPlayingSaved;
  bool? get nowPlayingSaved => _$this._nowPlayingSaved;
  set nowPlayingSaved(bool? nowPlayingSaved) =>
      _$this._nowPlayingSaved = nowPlayingSaved;

  String? _nowPlayingSavedPid;
  String? get nowPlayingSavedPid => _$this._nowPlayingSavedPid;
  set nowPlayingSavedPid(String? nowPlayingSavedPid) =>
      _$this._nowPlayingSavedPid = nowPlayingSavedPid;

  RadioPlayInfoBuilder() {
    RadioPlayInfo._defaults(this);
  }

  RadioPlayInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _url = $v.url;
      _nowPlaying = $v.nowPlaying;
      _nowPlayingItemPid = $v.nowPlayingItemPid;
      _nowPlayingArtKey = $v.nowPlayingArtKey;
      _nowPlayingSaved = $v.nowPlayingSaved;
      _nowPlayingSavedPid = $v.nowPlayingSavedPid;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RadioPlayInfo other) {
    _$v = other as _$RadioPlayInfo;
  }

  @override
  void update(void Function(RadioPlayInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RadioPlayInfo build() => _build();

  _$RadioPlayInfo _build() {
    final _$result =
        _$v ??
        _$RadioPlayInfo._(
          url: BuiltValueNullFieldError.checkNotNull(
            url,
            r'RadioPlayInfo',
            'url',
          ),
          nowPlaying: nowPlaying,
          nowPlayingItemPid: nowPlayingItemPid,
          nowPlayingArtKey: nowPlayingArtKey,
          nowPlayingSaved: nowPlayingSaved,
          nowPlayingSavedPid: nowPlayingSavedPid,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
