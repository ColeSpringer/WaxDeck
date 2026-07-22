// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'similarity_work_item.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SimilarityWorkItem extends SimilarityWorkItem {
  @override
  final String pid;
  @override
  final String essence;
  @override
  final String audioUrl;
  @override
  final String? localPath;
  @override
  final int durationMs;
  @override
  final MediaType mediaType;

  factory _$SimilarityWorkItem([
    void Function(SimilarityWorkItemBuilder)? updates,
  ]) => (SimilarityWorkItemBuilder()..update(updates))._build();

  _$SimilarityWorkItem._({
    required this.pid,
    required this.essence,
    required this.audioUrl,
    this.localPath,
    required this.durationMs,
    required this.mediaType,
  }) : super._();
  @override
  SimilarityWorkItem rebuild(
    void Function(SimilarityWorkItemBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  SimilarityWorkItemBuilder toBuilder() =>
      SimilarityWorkItemBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SimilarityWorkItem &&
        pid == other.pid &&
        essence == other.essence &&
        audioUrl == other.audioUrl &&
        localPath == other.localPath &&
        durationMs == other.durationMs &&
        mediaType == other.mediaType;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, essence.hashCode);
    _$hash = $jc(_$hash, audioUrl.hashCode);
    _$hash = $jc(_$hash, localPath.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SimilarityWorkItem')
          ..add('pid', pid)
          ..add('essence', essence)
          ..add('audioUrl', audioUrl)
          ..add('localPath', localPath)
          ..add('durationMs', durationMs)
          ..add('mediaType', mediaType))
        .toString();
  }
}

class SimilarityWorkItemBuilder
    implements Builder<SimilarityWorkItem, SimilarityWorkItemBuilder> {
  _$SimilarityWorkItem? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _essence;
  String? get essence => _$this._essence;
  set essence(String? essence) => _$this._essence = essence;

  String? _audioUrl;
  String? get audioUrl => _$this._audioUrl;
  set audioUrl(String? audioUrl) => _$this._audioUrl = audioUrl;

  String? _localPath;
  String? get localPath => _$this._localPath;
  set localPath(String? localPath) => _$this._localPath = localPath;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  MediaType? _mediaType;
  MediaType? get mediaType => _$this._mediaType;
  set mediaType(MediaType? mediaType) => _$this._mediaType = mediaType;

  SimilarityWorkItemBuilder() {
    SimilarityWorkItem._defaults(this);
  }

  SimilarityWorkItemBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _essence = $v.essence;
      _audioUrl = $v.audioUrl;
      _localPath = $v.localPath;
      _durationMs = $v.durationMs;
      _mediaType = $v.mediaType;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SimilarityWorkItem other) {
    _$v = other as _$SimilarityWorkItem;
  }

  @override
  void update(void Function(SimilarityWorkItemBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SimilarityWorkItem build() => _build();

  _$SimilarityWorkItem _build() {
    final _$result =
        _$v ??
        _$SimilarityWorkItem._(
          pid: BuiltValueNullFieldError.checkNotNull(
            pid,
            r'SimilarityWorkItem',
            'pid',
          ),
          essence: BuiltValueNullFieldError.checkNotNull(
            essence,
            r'SimilarityWorkItem',
            'essence',
          ),
          audioUrl: BuiltValueNullFieldError.checkNotNull(
            audioUrl,
            r'SimilarityWorkItem',
            'audioUrl',
          ),
          localPath: localPath,
          durationMs: BuiltValueNullFieldError.checkNotNull(
            durationMs,
            r'SimilarityWorkItem',
            'durationMs',
          ),
          mediaType: BuiltValueNullFieldError.checkNotNull(
            mediaType,
            r'SimilarityWorkItem',
            'mediaType',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
