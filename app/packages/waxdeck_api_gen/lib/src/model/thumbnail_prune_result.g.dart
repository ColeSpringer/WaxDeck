// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thumbnail_prune_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ThumbnailPruneResult extends ThumbnailPruneResult {
  @override
  final int removed;
  @override
  final int freedBytes;

  factory _$ThumbnailPruneResult([
    void Function(ThumbnailPruneResultBuilder)? updates,
  ]) => (ThumbnailPruneResultBuilder()..update(updates))._build();

  _$ThumbnailPruneResult._({required this.removed, required this.freedBytes})
    : super._();
  @override
  ThumbnailPruneResult rebuild(
    void Function(ThumbnailPruneResultBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ThumbnailPruneResultBuilder toBuilder() =>
      ThumbnailPruneResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ThumbnailPruneResult &&
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
    return (newBuiltValueToStringHelper(r'ThumbnailPruneResult')
          ..add('removed', removed)
          ..add('freedBytes', freedBytes))
        .toString();
  }
}

class ThumbnailPruneResultBuilder
    implements Builder<ThumbnailPruneResult, ThumbnailPruneResultBuilder> {
  _$ThumbnailPruneResult? _$v;

  int? _removed;
  int? get removed => _$this._removed;
  set removed(int? removed) => _$this._removed = removed;

  int? _freedBytes;
  int? get freedBytes => _$this._freedBytes;
  set freedBytes(int? freedBytes) => _$this._freedBytes = freedBytes;

  ThumbnailPruneResultBuilder() {
    ThumbnailPruneResult._defaults(this);
  }

  ThumbnailPruneResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _removed = $v.removed;
      _freedBytes = $v.freedBytes;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ThumbnailPruneResult other) {
    _$v = other as _$ThumbnailPruneResult;
  }

  @override
  void update(void Function(ThumbnailPruneResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ThumbnailPruneResult build() => _build();

  _$ThumbnailPruneResult _build() {
    final _$result =
        _$v ??
        _$ThumbnailPruneResult._(
          removed: BuiltValueNullFieldError.checkNotNull(
            removed,
            r'ThumbnailPruneResult',
            'removed',
          ),
          freedBytes: BuiltValueNullFieldError.checkNotNull(
            freedBytes,
            r'ThumbnailPruneResult',
            'freedBytes',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
