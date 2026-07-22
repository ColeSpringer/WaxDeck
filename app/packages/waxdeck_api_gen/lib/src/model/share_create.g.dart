// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'share_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ShareCreate extends ShareCreate {
  @override
  final String pid;
  @override
  final int? expiresInHours;
  @override
  final bool? allowDownload;
  @override
  final int? positionMs;

  factory _$ShareCreate([void Function(ShareCreateBuilder)? updates]) =>
      (ShareCreateBuilder()..update(updates))._build();

  _$ShareCreate._({
    required this.pid,
    this.expiresInHours,
    this.allowDownload,
    this.positionMs,
  }) : super._();
  @override
  ShareCreate rebuild(void Function(ShareCreateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ShareCreateBuilder toBuilder() => ShareCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ShareCreate &&
        pid == other.pid &&
        expiresInHours == other.expiresInHours &&
        allowDownload == other.allowDownload &&
        positionMs == other.positionMs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, expiresInHours.hashCode);
    _$hash = $jc(_$hash, allowDownload.hashCode);
    _$hash = $jc(_$hash, positionMs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ShareCreate')
          ..add('pid', pid)
          ..add('expiresInHours', expiresInHours)
          ..add('allowDownload', allowDownload)
          ..add('positionMs', positionMs))
        .toString();
  }
}

class ShareCreateBuilder implements Builder<ShareCreate, ShareCreateBuilder> {
  _$ShareCreate? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  int? _expiresInHours;
  int? get expiresInHours => _$this._expiresInHours;
  set expiresInHours(int? expiresInHours) =>
      _$this._expiresInHours = expiresInHours;

  bool? _allowDownload;
  bool? get allowDownload => _$this._allowDownload;
  set allowDownload(bool? allowDownload) =>
      _$this._allowDownload = allowDownload;

  int? _positionMs;
  int? get positionMs => _$this._positionMs;
  set positionMs(int? positionMs) => _$this._positionMs = positionMs;

  ShareCreateBuilder() {
    ShareCreate._defaults(this);
  }

  ShareCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _expiresInHours = $v.expiresInHours;
      _allowDownload = $v.allowDownload;
      _positionMs = $v.positionMs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ShareCreate other) {
    _$v = other as _$ShareCreate;
  }

  @override
  void update(void Function(ShareCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ShareCreate build() => _build();

  _$ShareCreate _build() {
    final _$result =
        _$v ??
        _$ShareCreate._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'ShareCreate',
            'pid',
          ),
          expiresInHours: expiresInHours,
          allowDownload: allowDownload,
          positionMs: positionMs,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
