// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_cache_report.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentCacheReport extends EnrichmentCacheReport {
  @override
  final int rows;
  @override
  final int bytes;
  @override
  final DateTime? oldestAt;
  @override
  final DateTime? newestAt;
  @override
  final BuiltList<EnrichmentCacheKind> kinds;
  @override
  final int exemptRows;
  @override
  final int exemptBytes;

  factory _$EnrichmentCacheReport([
    void Function(EnrichmentCacheReportBuilder)? updates,
  ]) => (EnrichmentCacheReportBuilder()..update(updates))._build();

  _$EnrichmentCacheReport._({
    required this.rows,
    required this.bytes,
    this.oldestAt,
    this.newestAt,
    required this.kinds,
    required this.exemptRows,
    required this.exemptBytes,
  }) : super._();
  @override
  EnrichmentCacheReport rebuild(
    void Function(EnrichmentCacheReportBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EnrichmentCacheReportBuilder toBuilder() =>
      EnrichmentCacheReportBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentCacheReport &&
        rows == other.rows &&
        bytes == other.bytes &&
        oldestAt == other.oldestAt &&
        newestAt == other.newestAt &&
        kinds == other.kinds &&
        exemptRows == other.exemptRows &&
        exemptBytes == other.exemptBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, rows.hashCode);
    _$hash = $jc(_$hash, bytes.hashCode);
    _$hash = $jc(_$hash, oldestAt.hashCode);
    _$hash = $jc(_$hash, newestAt.hashCode);
    _$hash = $jc(_$hash, kinds.hashCode);
    _$hash = $jc(_$hash, exemptRows.hashCode);
    _$hash = $jc(_$hash, exemptBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichmentCacheReport')
          ..add('rows', rows)
          ..add('bytes', bytes)
          ..add('oldestAt', oldestAt)
          ..add('newestAt', newestAt)
          ..add('kinds', kinds)
          ..add('exemptRows', exemptRows)
          ..add('exemptBytes', exemptBytes))
        .toString();
  }
}

class EnrichmentCacheReportBuilder
    implements Builder<EnrichmentCacheReport, EnrichmentCacheReportBuilder> {
  _$EnrichmentCacheReport? _$v;

  int? _rows;
  int? get rows => _$this._rows;
  set rows(int? rows) => _$this._rows = rows;

  int? _bytes;
  int? get bytes => _$this._bytes;
  set bytes(int? bytes) => _$this._bytes = bytes;

  DateTime? _oldestAt;
  DateTime? get oldestAt => _$this._oldestAt;
  set oldestAt(DateTime? oldestAt) => _$this._oldestAt = oldestAt;

  DateTime? _newestAt;
  DateTime? get newestAt => _$this._newestAt;
  set newestAt(DateTime? newestAt) => _$this._newestAt = newestAt;

  ListBuilder<EnrichmentCacheKind>? _kinds;
  ListBuilder<EnrichmentCacheKind> get kinds =>
      _$this._kinds ??= ListBuilder<EnrichmentCacheKind>();
  set kinds(ListBuilder<EnrichmentCacheKind>? kinds) => _$this._kinds = kinds;

  int? _exemptRows;
  int? get exemptRows => _$this._exemptRows;
  set exemptRows(int? exemptRows) => _$this._exemptRows = exemptRows;

  int? _exemptBytes;
  int? get exemptBytes => _$this._exemptBytes;
  set exemptBytes(int? exemptBytes) => _$this._exemptBytes = exemptBytes;

  EnrichmentCacheReportBuilder() {
    EnrichmentCacheReport._defaults(this);
  }

  EnrichmentCacheReportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _rows = $v.rows;
      _bytes = $v.bytes;
      _oldestAt = $v.oldestAt;
      _newestAt = $v.newestAt;
      _kinds = $v.kinds.toBuilder();
      _exemptRows = $v.exemptRows;
      _exemptBytes = $v.exemptBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentCacheReport other) {
    _$v = other as _$EnrichmentCacheReport;
  }

  @override
  void update(void Function(EnrichmentCacheReportBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentCacheReport build() => _build();

  _$EnrichmentCacheReport _build() {
    _$EnrichmentCacheReport _$result;
    try {
      _$result =
          _$v ??
          _$EnrichmentCacheReport._(
            rows: BuiltValueNullFieldError.checkNotNull(
              rows,
              r'EnrichmentCacheReport',
              'rows',
            ),
            bytes: BuiltValueNullFieldError.checkNotNull(
              bytes,
              r'EnrichmentCacheReport',
              'bytes',
            ),
            oldestAt: oldestAt,
            newestAt: newestAt,
            kinds: kinds.build(),
            exemptRows: BuiltValueNullFieldError.checkNotNull(
              exemptRows,
              r'EnrichmentCacheReport',
              'exemptRows',
            ),
            exemptBytes: BuiltValueNullFieldError.checkNotNull(
              exemptBytes,
              r'EnrichmentCacheReport',
              'exemptBytes',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'kinds';
        kinds.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EnrichmentCacheReport',
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
