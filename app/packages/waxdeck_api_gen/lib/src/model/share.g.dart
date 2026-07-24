// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'share.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Share extends Share {
  @override
  final String pid;
  @override
  final String url;
  @override
  final String targetPid;
  @override
  final String targetKind;
  @override
  final String targetTitle;
  @override
  final bool allowDownload;
  @override
  final int? positionMs;
  @override
  final DateTime createdAt;
  @override
  final DateTime? expiresAt;
  @override
  final int plays;

  factory _$Share([void Function(ShareBuilder)? updates]) =>
      (ShareBuilder()..update(updates))._build();

  _$Share._({
    required this.pid,
    required this.url,
    required this.targetPid,
    required this.targetKind,
    required this.targetTitle,
    required this.allowDownload,
    this.positionMs,
    required this.createdAt,
    this.expiresAt,
    required this.plays,
  }) : super._();
  @override
  Share rebuild(void Function(ShareBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ShareBuilder toBuilder() => ShareBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Share &&
        pid == other.pid &&
        url == other.url &&
        targetPid == other.targetPid &&
        targetKind == other.targetKind &&
        targetTitle == other.targetTitle &&
        allowDownload == other.allowDownload &&
        positionMs == other.positionMs &&
        createdAt == other.createdAt &&
        expiresAt == other.expiresAt &&
        plays == other.plays;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, targetPid.hashCode);
    _$hash = $jc(_$hash, targetKind.hashCode);
    _$hash = $jc(_$hash, targetTitle.hashCode);
    _$hash = $jc(_$hash, allowDownload.hashCode);
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jc(_$hash, plays.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Share')
          ..add('pid', pid)
          ..add('url', url)
          ..add('targetPid', targetPid)
          ..add('targetKind', targetKind)
          ..add('targetTitle', targetTitle)
          ..add('allowDownload', allowDownload)
          ..add('positionMs', positionMs)
          ..add('createdAt', createdAt)
          ..add('expiresAt', expiresAt)
          ..add('plays', plays))
        .toString();
  }
}

class ShareBuilder implements Builder<Share, ShareBuilder> {
  _$Share? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _targetPid;
  String? get targetPid => _$this._targetPid;
  set targetPid(String? targetPid) => _$this._targetPid = targetPid;

  String? _targetKind;
  String? get targetKind => _$this._targetKind;
  set targetKind(String? targetKind) => _$this._targetKind = targetKind;

  String? _targetTitle;
  String? get targetTitle => _$this._targetTitle;
  set targetTitle(String? targetTitle) => _$this._targetTitle = targetTitle;

  bool? _allowDownload;
  bool? get allowDownload => _$this._allowDownload;
  set allowDownload(bool? allowDownload) =>
      _$this._allowDownload = allowDownload;

  int? _positionMs;
  int? get positionMs => _$this._positionMs;
  set positionMs(int? positionMs) => _$this._positionMs = positionMs;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  int? _plays;
  int? get plays => _$this._plays;
  set plays(int? plays) => _$this._plays = plays;

  ShareBuilder() {
    Share._defaults(this);
  }

  ShareBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _url = $v.url;
      _targetPid = $v.targetPid;
      _targetKind = $v.targetKind;
      _targetTitle = $v.targetTitle;
      _allowDownload = $v.allowDownload;
      _positionMs = $v.positionMs;
      _createdAt = $v.createdAt;
      _expiresAt = $v.expiresAt;
      _plays = $v.plays;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Share other) {
    _$v = other as _$Share;
  }

  @override
  void update(void Function(ShareBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Share build() => _build();

  _$Share _build() {
    final _$result =
        _$v ??
        _$Share._(
          pid: BuiltValueNullFieldError.checkNotNull(pid, r'Share', 'pid'),
          url: BuiltValueNullFieldError.checkNotNull(url, r'Share', 'url'),
          targetPid: BuiltValueNullFieldError.checkNotNull(
            targetPid,
            r'Share',
            'targetPid',
          ),
          targetKind: BuiltValueNullFieldError.checkNotNull(
            targetKind,
            r'Share',
            'targetKind',
          ),
          targetTitle: BuiltValueNullFieldError.checkNotNull(
            targetTitle,
            r'Share',
            'targetTitle',
          ),
          allowDownload: BuiltValueNullFieldError.checkNotNull(
            allowDownload,
            r'Share',
            'allowDownload',
          ),
          positionMs: positionMs,
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'Share',
            'createdAt',
          ),
          expiresAt: expiresAt,
          plays: BuiltValueNullFieldError.checkNotNull(
            plays,
            r'Share',
            'plays',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
