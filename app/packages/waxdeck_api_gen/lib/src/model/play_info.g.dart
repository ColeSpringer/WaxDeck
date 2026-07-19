// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'play_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlayInfo extends PlayInfo {
  @override
  final String pid;
  @override
  final String url;
  @override
  final String mimeType;
  @override
  final int durationMs;
  @override
  final bool seekable;
  @override
  final DateTime expiresAt;
  @override
  final int? partIndex;
  @override
  final int? partCount;
  @override
  final int? partStartMs;
  @override
  final bool? voiceBoost;
  @override
  final int? spanStartMs;
  @override
  final int? spanEndMs;

  factory _$PlayInfo([void Function(PlayInfoBuilder)? updates]) =>
      (PlayInfoBuilder()..update(updates))._build();

  _$PlayInfo._({
    required this.pid,
    required this.url,
    required this.mimeType,
    required this.durationMs,
    required this.seekable,
    required this.expiresAt,
    this.partIndex,
    this.partCount,
    this.partStartMs,
    this.voiceBoost,
    this.spanStartMs,
    this.spanEndMs,
  }) : super._();
  @override
  PlayInfo rebuild(void Function(PlayInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlayInfoBuilder toBuilder() => PlayInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlayInfo &&
        pid == other.pid &&
        url == other.url &&
        mimeType == other.mimeType &&
        durationMs == other.durationMs &&
        seekable == other.seekable &&
        expiresAt == other.expiresAt &&
        partIndex == other.partIndex &&
        partCount == other.partCount &&
        partStartMs == other.partStartMs &&
        voiceBoost == other.voiceBoost &&
        spanStartMs == other.spanStartMs &&
        spanEndMs == other.spanEndMs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, mimeType.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jc(_$hash, seekable.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jc(_$hash, partIndex.hashCode);
    _$hash = $jc(_$hash, partCount.hashCode);
    _$hash = $jc(_$hash, partStartMs.hashCode);
    _$hash = $jc(_$hash, voiceBoost.hashCode);
    _$hash = $jc(_$hash, spanStartMs.hashCode);
    _$hash = $jc(_$hash, spanEndMs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlayInfo')
          ..add('pid', pid)
          ..add('url', url)
          ..add('mimeType', mimeType)
          ..add('durationMs', durationMs)
          ..add('seekable', seekable)
          ..add('expiresAt', expiresAt)
          ..add('partIndex', partIndex)
          ..add('partCount', partCount)
          ..add('partStartMs', partStartMs)
          ..add('voiceBoost', voiceBoost)
          ..add('spanStartMs', spanStartMs)
          ..add('spanEndMs', spanEndMs))
        .toString();
  }
}

class PlayInfoBuilder implements Builder<PlayInfo, PlayInfoBuilder> {
  _$PlayInfo? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _mimeType;
  String? get mimeType => _$this._mimeType;
  set mimeType(String? mimeType) => _$this._mimeType = mimeType;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  bool? _seekable;
  bool? get seekable => _$this._seekable;
  set seekable(bool? seekable) => _$this._seekable = seekable;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  int? _partIndex;
  int? get partIndex => _$this._partIndex;
  set partIndex(int? partIndex) => _$this._partIndex = partIndex;

  int? _partCount;
  int? get partCount => _$this._partCount;
  set partCount(int? partCount) => _$this._partCount = partCount;

  int? _partStartMs;
  int? get partStartMs => _$this._partStartMs;
  set partStartMs(int? partStartMs) => _$this._partStartMs = partStartMs;

  bool? _voiceBoost;
  bool? get voiceBoost => _$this._voiceBoost;
  set voiceBoost(bool? voiceBoost) => _$this._voiceBoost = voiceBoost;

  int? _spanStartMs;
  int? get spanStartMs => _$this._spanStartMs;
  set spanStartMs(int? spanStartMs) => _$this._spanStartMs = spanStartMs;

  int? _spanEndMs;
  int? get spanEndMs => _$this._spanEndMs;
  set spanEndMs(int? spanEndMs) => _$this._spanEndMs = spanEndMs;

  PlayInfoBuilder() {
    PlayInfo._defaults(this);
  }

  PlayInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _url = $v.url;
      _mimeType = $v.mimeType;
      _durationMs = $v.durationMs;
      _seekable = $v.seekable;
      _expiresAt = $v.expiresAt;
      _partIndex = $v.partIndex;
      _partCount = $v.partCount;
      _partStartMs = $v.partStartMs;
      _voiceBoost = $v.voiceBoost;
      _spanStartMs = $v.spanStartMs;
      _spanEndMs = $v.spanEndMs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlayInfo other) {
    _$v = other as _$PlayInfo;
  }

  @override
  void update(void Function(PlayInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlayInfo build() => _build();

  _$PlayInfo _build() {
    final _$result =
        _$v ??
        _$PlayInfo._(
          pid: BuiltValueNullFieldError.checkNotNull(pid, r'PlayInfo', 'pid'),
          url: BuiltValueNullFieldError.checkNotNull(url, r'PlayInfo', 'url'),
          mimeType: BuiltValueNullFieldError.checkNotNull(
            mimeType,
            r'PlayInfo',
            'mimeType',
          ),
          durationMs: BuiltValueNullFieldError.checkNotNull(
            durationMs,
            r'PlayInfo',
            'durationMs',
          ),
          seekable: BuiltValueNullFieldError.checkNotNull(
            seekable,
            r'PlayInfo',
            'seekable',
          ),
          expiresAt: BuiltValueNullFieldError.checkNotNull(
            expiresAt,
            r'PlayInfo',
            'expiresAt',
          ),
          partIndex: partIndex,
          partCount: partCount,
          partStartMs: partStartMs,
          voiceBoost: voiceBoost,
          spanStartMs: spanStartMs,
          spanEndMs: spanEndMs,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
