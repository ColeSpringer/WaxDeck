// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_cache_prune_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentCachePruneResult extends EnrichmentCachePruneResult {
  @override
  final int removed;
  @override
  final int freedBytes;

  factory _$EnrichmentCachePruneResult([
    void Function(EnrichmentCachePruneResultBuilder)? updates,
  ]) => (EnrichmentCachePruneResultBuilder()..update(updates))._build();

  _$EnrichmentCachePruneResult._({
    required this.removed,
    required this.freedBytes,
  }) : super._();
  @override
  EnrichmentCachePruneResult rebuild(
    void Function(EnrichmentCachePruneResultBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EnrichmentCachePruneResultBuilder toBuilder() =>
      EnrichmentCachePruneResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentCachePruneResult &&
        removed == other.removed &&
        freedBytes == other.freedBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, removed.hashCode);
    _$hash = $jc(_$hash, freedBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichmentCachePruneResult')
          ..add('removed', removed)
          ..add('freedBytes', freedBytes))
        .toString();
  }
}

class EnrichmentCachePruneResultBuilder
    implements
        Builder<EnrichmentCachePruneResult, EnrichmentCachePruneResultBuilder> {
  _$EnrichmentCachePruneResult? _$v;

  int? _removed;
  int? get removed => _$this._removed;
  set removed(int? removed) => _$this._removed = removed;

  int? _freedBytes;
  int? get freedBytes => _$this._freedBytes;
  set freedBytes(int? freedBytes) => _$this._freedBytes = freedBytes;

  EnrichmentCachePruneResultBuilder() {
    EnrichmentCachePruneResult._defaults(this);
  }

  EnrichmentCachePruneResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _removed = $v.removed;
      _freedBytes = $v.freedBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentCachePruneResult other) {
    _$v = other as _$EnrichmentCachePruneResult;
  }

  @override
  void update(void Function(EnrichmentCachePruneResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentCachePruneResult build() => _build();

  _$EnrichmentCachePruneResult _build() {
    final _$result =
        _$v ??
        _$EnrichmentCachePruneResult._(
          removed: BuiltValueNullFieldError.checkNotNull(
            removed,
            r'EnrichmentCachePruneResult',
            'removed',
          ),
          freedBytes: BuiltValueNullFieldError.checkNotNull(
            freedBytes,
            r'EnrichmentCachePruneResult',
            'freedBytes',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
