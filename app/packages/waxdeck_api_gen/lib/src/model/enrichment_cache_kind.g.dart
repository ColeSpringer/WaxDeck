// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_cache_kind.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentCacheKind extends EnrichmentCacheKind {
  @override
  final String kind;
  @override
  final int rows;
  @override
  final int bytes;
  @override
  final bool exempt;

  factory _$EnrichmentCacheKind([
    void Function(EnrichmentCacheKindBuilder)? updates,
  ]) => (EnrichmentCacheKindBuilder()..update(updates))._build();

  _$EnrichmentCacheKind._({
    required this.kind,
    required this.rows,
    required this.bytes,
    required this.exempt,
  }) : super._();
  @override
  EnrichmentCacheKind rebuild(
    void Function(EnrichmentCacheKindBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EnrichmentCacheKindBuilder toBuilder() =>
      EnrichmentCacheKindBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentCacheKind &&
        kind == other.kind &&
        rows == other.rows &&
        bytes == other.bytes &&
        exempt == other.exempt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, rows.hashCode);
    _$hash = $jc(_$hash, bytes.hashCode);
    _$hash = $jc(_$hash, exempt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichmentCacheKind')
          ..add('kind', kind)
          ..add('rows', rows)
          ..add('bytes', bytes)
          ..add('exempt', exempt))
        .toString();
  }
}

class EnrichmentCacheKindBuilder
    implements Builder<EnrichmentCacheKind, EnrichmentCacheKindBuilder> {
  _$EnrichmentCacheKind? _$v;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  int? _rows;
  int? get rows => _$this._rows;
  set rows(int? rows) => _$this._rows = rows;

  int? _bytes;
  int? get bytes => _$this._bytes;
  set bytes(int? bytes) => _$this._bytes = bytes;

  bool? _exempt;
  bool? get exempt => _$this._exempt;
  set exempt(bool? exempt) => _$this._exempt = exempt;

  EnrichmentCacheKindBuilder() {
    EnrichmentCacheKind._defaults(this);
  }

  EnrichmentCacheKindBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _rows = $v.rows;
      _bytes = $v.bytes;
      _exempt = $v.exempt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentCacheKind other) {
    _$v = other as _$EnrichmentCacheKind;
  }

  @override
  void update(void Function(EnrichmentCacheKindBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentCacheKind build() => _build();

  _$EnrichmentCacheKind _build() {
    final _$result =
        _$v ??
        _$EnrichmentCacheKind._(
          kind: BuiltValueNullFieldError.checkNotNull(
            kind,
            r'EnrichmentCacheKind',
            'kind',
          ),
          rows: BuiltValueNullFieldError.checkNotNull(
            rows,
            r'EnrichmentCacheKind',
            'rows',
          ),
          bytes: BuiltValueNullFieldError.checkNotNull(
            bytes,
            r'EnrichmentCacheKind',
            'bytes',
          ),
          exempt: BuiltValueNullFieldError.checkNotNull(
            exempt,
            r'EnrichmentCacheKind',
            'exempt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
