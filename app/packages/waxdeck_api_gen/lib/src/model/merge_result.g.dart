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
  @override
  final BuiltList<String> folds;

  factory _$MergeResult([void Function(MergeResultBuilder)? updates]) =>
      (MergeResultBuilder()..update(updates))._build();

  _$MergeResult._({
    required this.merged,
    required this.childrenMoved,
    required this.folds,
  }) : super._();
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
        childrenMoved == other.childrenMoved &&
        folds == other.folds;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, merged.hashCode);
    _$hash = $jc(_$hash, childrenMoved.hashCode);
    _$hash = $jc(_$hash, folds.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MergeResult')
          ..add('merged', merged)
          ..add('childrenMoved', childrenMoved)
          ..add('folds', folds))
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

  ListBuilder<String>? _folds;
  ListBuilder<String> get folds => _$this._folds ??= ListBuilder<String>();
  set folds(ListBuilder<String>? folds) => _$this._folds = folds;

  MergeResultBuilder() {
    MergeResult._defaults(this);
  }

  MergeResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _merged = $v.merged;
      _childrenMoved = $v.childrenMoved;
      _folds = $v.folds.toBuilder();
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
    _$MergeResult _$result;
    try {
      _$result =
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
            folds: folds.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'folds';
        folds.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'MergeResult',
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
