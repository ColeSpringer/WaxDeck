// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'merge_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MergeResult extends MergeResult {
  @override
  final int merged;
  @override
  final int childrenMoved;

  factory _$MergeResult([void Function(MergeResultBuilder)? updates]) =>
      (MergeResultBuilder()..update(updates))._build();

  _$MergeResult._({required this.merged, required this.childrenMoved})
    : super._();
  @override
  MergeResult rebuild(void Function(MergeResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MergeResultBuilder toBuilder() => MergeResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MergeResult &&
        merged == other.merged &&
        childrenMoved == other.childrenMoved;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, merged.hashCode);
    _$hash = $jc(_$hash, childrenMoved.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MergeResult')
          ..add('merged', merged)
          ..add('childrenMoved', childrenMoved))
        .toString();
  }
}

class MergeResultBuilder implements Builder<MergeResult, MergeResultBuilder> {
  _$MergeResult? _$v;

  int? _merged;
  int? get merged => _$this._merged;
  set merged(int? merged) => _$this._merged = merged;

  int? _childrenMoved;
  int? get childrenMoved => _$this._childrenMoved;
  set childrenMoved(int? childrenMoved) =>
      _$this._childrenMoved = childrenMoved;

  MergeResultBuilder() {
    MergeResult._defaults(this);
  }

  MergeResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _merged = $v.merged;
      _childrenMoved = $v.childrenMoved;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MergeResult other) {
    _$v = other as _$MergeResult;
  }

  @override
  void update(void Function(MergeResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MergeResult build() => _build();

  _$MergeResult _build() {
    final _$result =
        _$v ??
        _$MergeResult._(
          merged: BuiltValueNullFieldError.checkNotNull(
            merged,
            r'MergeResult',
            'merged',
          ),
          childrenMoved: BuiltValueNullFieldError.checkNotNull(
            childrenMoved,
            r'MergeResult',
            'childrenMoved',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
