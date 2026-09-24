// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_cache_prune_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EnrichmentCachePruneRequest extends EnrichmentCachePruneRequest {
  @override
  final int? olderThanSeconds;
  @override
  final int? maxBytes;

  factory _$EnrichmentCachePruneRequest([
    void Function(EnrichmentCachePruneRequestBuilder)? updates,
  ]) => (EnrichmentCachePruneRequestBuilder()..update(updates))._build();

  _$EnrichmentCachePruneRequest._({this.olderThanSeconds, this.maxBytes})
    : super._();
  @override
  EnrichmentCachePruneRequest rebuild(
    void Function(EnrichmentCachePruneRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  EnrichmentCachePruneRequestBuilder toBuilder() =>
      EnrichmentCachePruneRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EnrichmentCachePruneRequest &&
        olderThanSeconds == other.olderThanSeconds &&
        maxBytes == other.maxBytes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, olderThanSeconds.hashCode);
    _$hash = $jc(_$hash, maxBytes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EnrichmentCachePruneRequest')
          ..add('olderThanSeconds', olderThanSeconds)
          ..add('maxBytes', maxBytes))
        .toString();
  }
}

class EnrichmentCachePruneRequestBuilder
    implements
        Builder<
          EnrichmentCachePruneRequest,
          EnrichmentCachePruneRequestBuilder
        > {
  _$EnrichmentCachePruneRequest? _$v;

  int? _olderThanSeconds;
  int? get olderThanSeconds => _$this._olderThanSeconds;
  set olderThanSeconds(int? olderThanSeconds) =>
      _$this._olderThanSeconds = olderThanSeconds;

  int? _maxBytes;
  int? get maxBytes => _$this._maxBytes;
  set maxBytes(int? maxBytes) => _$this._maxBytes = maxBytes;

  EnrichmentCachePruneRequestBuilder() {
    EnrichmentCachePruneRequest._defaults(this);
  }

  EnrichmentCachePruneRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _olderThanSeconds = $v.olderThanSeconds;
      _maxBytes = $v.maxBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EnrichmentCachePruneRequest other) {
    _$v = other as _$EnrichmentCachePruneRequest;
  }

  @override
  void update(void Function(EnrichmentCachePruneRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EnrichmentCachePruneRequest build() => _build();

  _$EnrichmentCachePruneRequest _build() {
    final _$result =
        _$v ??
        _$EnrichmentCachePruneRequest._(
          olderThanSeconds: olderThanSeconds,
          maxBytes: maxBytes,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
