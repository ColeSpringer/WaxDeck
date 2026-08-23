// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thumbnail_prune_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ThumbnailPruneRequest extends ThumbnailPruneRequest {
  @override
  final int? olderThanSeconds;
  @override
  final int? maxBytes;

  factory _$ThumbnailPruneRequest([
    void Function(ThumbnailPruneRequestBuilder)? updates,
  ]) => (ThumbnailPruneRequestBuilder()..update(updates))._build();

  _$ThumbnailPruneRequest._({this.olderThanSeconds, this.maxBytes}) : super._();
  @override
  ThumbnailPruneRequest rebuild(
    void Function(ThumbnailPruneRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ThumbnailPruneRequestBuilder toBuilder() =>
      ThumbnailPruneRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ThumbnailPruneRequest &&
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
    return (newBuiltValueToStringHelper(r'ThumbnailPruneRequest')
          ..add('olderThanSeconds', olderThanSeconds)
          ..add('maxBytes', maxBytes))
        .toString();
  }
}

class ThumbnailPruneRequestBuilder
    implements Builder<ThumbnailPruneRequest, ThumbnailPruneRequestBuilder> {
  _$ThumbnailPruneRequest? _$v;

  int? _olderThanSeconds;
  int? get olderThanSeconds => _$this._olderThanSeconds;
  set olderThanSeconds(int? olderThanSeconds) =>
      _$this._olderThanSeconds = olderThanSeconds;

  int? _maxBytes;
  int? get maxBytes => _$this._maxBytes;
  set maxBytes(int? maxBytes) => _$this._maxBytes = maxBytes;

  ThumbnailPruneRequestBuilder() {
    ThumbnailPruneRequest._defaults(this);
  }

  ThumbnailPruneRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _olderThanSeconds = $v.olderThanSeconds;
      _maxBytes = $v.maxBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ThumbnailPruneRequest other) {
    _$v = other as _$ThumbnailPruneRequest;
  }

  @override
  void update(void Function(ThumbnailPruneRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ThumbnailPruneRequest build() => _build();

  _$ThumbnailPruneRequest _build() {
    final _$result =
        _$v ??
        _$ThumbnailPruneRequest._(
          olderThanSeconds: olderThanSeconds,
          maxBytes: maxBytes,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
