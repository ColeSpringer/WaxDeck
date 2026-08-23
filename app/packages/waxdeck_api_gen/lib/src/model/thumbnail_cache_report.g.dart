// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thumbnail_cache_report.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ThumbnailCacheReport extends ThumbnailCacheReport {
  @override
  final int rows;
  @override
  final int bytes;
  @override
  final int sources;
  @override
  final int artSources;
  @override
  final int artSourceBytes;
  @override
  final DateTime? oldestAt;
  @override
  final DateTime? newestAt;
  @override
  final BuiltList<ThumbnailRung> rungs;

  factory _$ThumbnailCacheReport([
    void Function(ThumbnailCacheReportBuilder)? updates,
  ]) => (ThumbnailCacheReportBuilder()..update(updates))._build();

  _$ThumbnailCacheReport._({
    required this.rows,
    required this.bytes,
    required this.sources,
    required this.artSources,
    required this.artSourceBytes,
    this.oldestAt,
    this.newestAt,
    required this.rungs,
  }) : super._();
  @override
  ThumbnailCacheReport rebuild(
    void Function(ThumbnailCacheReportBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ThumbnailCacheReportBuilder toBuilder() =>
      ThumbnailCacheReportBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ThumbnailCacheReport &&
        rows == other.rows &&
        bytes == other.bytes &&
        sources == other.sources &&
        artSources == other.artSources &&
        artSourceBytes == other.artSourceBytes &&
        oldestAt == other.oldestAt &&
        newestAt == other.newestAt &&
        rungs == other.rungs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, rows.hashCode);
    _$hash = $jc(_$hash, bytes.hashCode);
    _$hash = $jc(_$hash, sources.hashCode);
    _$hash = $jc(_$hash, artSources.hashCode);
    _$hash = $jc(_$hash, artSourceBytes.hashCode);
    _$hash = $jc(_$hash, oldestAt.hashCode);
    _$hash = $jc(_$hash, newestAt.hashCode);
    _$hash = $jc(_$hash, rungs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ThumbnailCacheReport')
          ..add('rows', rows)
          ..add('bytes', bytes)
          ..add('sources', sources)
          ..add('artSources', artSources)
          ..add('artSourceBytes', artSourceBytes)
          ..add('oldestAt', oldestAt)
          ..add('newestAt', newestAt)
          ..add('rungs', rungs))
        .toString();
  }
}

class ThumbnailCacheReportBuilder
    implements Builder<ThumbnailCacheReport, ThumbnailCacheReportBuilder> {
  _$ThumbnailCacheReport? _$v;

  int? _rows;
  int? get rows => _$this._rows;
  set rows(int? rows) => _$this._rows = rows;

  int? _bytes;
  int? get bytes => _$this._bytes;
  set bytes(int? bytes) => _$this._bytes = bytes;

  int? _sources;
  int? get sources => _$this._sources;
  set sources(int? sources) => _$this._sources = sources;

  int? _artSources;
  int? get artSources => _$this._artSources;
  set artSources(int? artSources) => _$this._artSources = artSources;

  int? _artSourceBytes;
  int? get artSourceBytes => _$this._artSourceBytes;
  set artSourceBytes(int? artSourceBytes) =>
      _$this._artSourceBytes = artSourceBytes;

  DateTime? _oldestAt;
  DateTime? get oldestAt => _$this._oldestAt;
  set oldestAt(DateTime? oldestAt) => _$this._oldestAt = oldestAt;

  DateTime? _newestAt;
  DateTime? get newestAt => _$this._newestAt;
  set newestAt(DateTime? newestAt) => _$this._newestAt = newestAt;

  ListBuilder<ThumbnailRung>? _rungs;
  ListBuilder<ThumbnailRung> get rungs =>
      _$this._rungs ??= ListBuilder<ThumbnailRung>();
  set rungs(ListBuilder<ThumbnailRung>? rungs) => _$this._rungs = rungs;

  ThumbnailCacheReportBuilder() {
    ThumbnailCacheReport._defaults(this);
  }

  ThumbnailCacheReportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _rows = $v.rows;
      _bytes = $v.bytes;
      _sources = $v.sources;
      _artSources = $v.artSources;
      _artSourceBytes = $v.artSourceBytes;
      _oldestAt = $v.oldestAt;
      _newestAt = $v.newestAt;
      _rungs = $v.rungs.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ThumbnailCacheReport other) {
    _$v = other as _$ThumbnailCacheReport;
  }

  @override
  void update(void Function(ThumbnailCacheReportBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ThumbnailCacheReport build() => _build();

  _$ThumbnailCacheReport _build() {
    _$ThumbnailCacheReport _$result;
    try {
      _$result =
          _$v ??
          _$ThumbnailCacheReport._(
            rows: BuiltValueNullFieldError.checkNotNull(
              rows,
              r'ThumbnailCacheReport',
              'rows',
            ),
            bytes: BuiltValueNullFieldError.checkNotNull(
              bytes,
              r'ThumbnailCacheReport',
              'bytes',
            ),
            sources: BuiltValueNullFieldError.checkNotNull(
              sources,
              r'ThumbnailCacheReport',
              'sources',
            ),
            artSources: BuiltValueNullFieldError.checkNotNull(
              artSources,
              r'ThumbnailCacheReport',
              'artSources',
            ),
            artSourceBytes: BuiltValueNullFieldError.checkNotNull(
              artSourceBytes,
              r'ThumbnailCacheReport',
              'artSourceBytes',
            ),
            oldestAt: oldestAt,
            newestAt: newestAt,
            rungs: rungs.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'rungs';
        rungs.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ThumbnailCacheReport',
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
