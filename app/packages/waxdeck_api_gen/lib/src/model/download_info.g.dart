// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DownloadInfo extends DownloadInfo {
  @override
  final String pid;
  @override
  final BuiltList<DownloadFile> files;
  @override
  final int? spanStartMs;
  @override
  final int? spanEndMs;
  @override
  final DateTime expiresAt;

  factory _$DownloadInfo([void Function(DownloadInfoBuilder)? updates]) =>
      (DownloadInfoBuilder()..update(updates))._build();

  _$DownloadInfo._({
    required this.pid,
    required this.files,
    this.spanStartMs,
    this.spanEndMs,
    required this.expiresAt,
  }) : super._();
  @override
  DownloadInfo rebuild(void Function(DownloadInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DownloadInfoBuilder toBuilder() => DownloadInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DownloadInfo &&
        pid == other.pid &&
        files == other.files &&
        spanStartMs == other.spanStartMs &&
        spanEndMs == other.spanEndMs &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, files.hashCode);
    _$hash = $jc(_$hash, spanStartMs.hashCode);
    _$hash = $jc(_$hash, spanEndMs.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DownloadInfo')
          ..add('pid', pid)
          ..add('files', files)
          ..add('spanStartMs', spanStartMs)
          ..add('spanEndMs', spanEndMs)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class DownloadInfoBuilder
    implements Builder<DownloadInfo, DownloadInfoBuilder> {
  _$DownloadInfo? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  ListBuilder<DownloadFile>? _files;
  ListBuilder<DownloadFile> get files =>
      _$this._files ??= ListBuilder<DownloadFile>();
  set files(ListBuilder<DownloadFile>? files) => _$this._files = files;

  int? _spanStartMs;
  int? get spanStartMs => _$this._spanStartMs;
  set spanStartMs(int? spanStartMs) => _$this._spanStartMs = spanStartMs;

  int? _spanEndMs;
  int? get spanEndMs => _$this._spanEndMs;
  set spanEndMs(int? spanEndMs) => _$this._spanEndMs = spanEndMs;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  DownloadInfoBuilder() {
    DownloadInfo._defaults(this);
  }

  DownloadInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _files = $v.files.toBuilder();
      _spanStartMs = $v.spanStartMs;
      _spanEndMs = $v.spanEndMs;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DownloadInfo other) {
    _$v = other as _$DownloadInfo;
  }

  @override
  void update(void Function(DownloadInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DownloadInfo build() => _build();

  _$DownloadInfo _build() {
    _$DownloadInfo _$result;
    try {
      _$result =
          _$v ??
          _$DownloadInfo._(
            pid: BuiltValueNullFieldError.checkNotNull(
              pid,
              r'DownloadInfo',
              'pid',
            ),
            files: files.build(),
            spanStartMs: spanStartMs,
            spanEndMs: spanEndMs,
            expiresAt: BuiltValueNullFieldError.checkNotNull(
              expiresAt,
              r'DownloadInfo',
              'expiresAt',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'files';
        files.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'DownloadInfo',
          _$failedField,
          e.toString(),
        );
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
