// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_fold_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EntityFoldPage extends EntityFoldPage {
  @override
  final BuiltList<EntityFold> folds;
  @override
  final String? nextCursor;

  factory _$EntityFoldPage([void Function(EntityFoldPageBuilder)? updates]) =>
      (EntityFoldPageBuilder()..update(updates))._build();

  _$EntityFoldPage._({required this.folds, this.nextCursor}) : super._();
  @override
  EntityFoldPage rebuild(void Function(EntityFoldPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EntityFoldPageBuilder toBuilder() => EntityFoldPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EntityFoldPage &&
        folds == other.folds &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, folds.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EntityFoldPage')
          ..add('folds', folds)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class EntityFoldPageBuilder
    implements Builder<EntityFoldPage, EntityFoldPageBuilder> {
  _$EntityFoldPage? _$v;

  ListBuilder<EntityFold>? _folds;
  ListBuilder<EntityFold> get folds =>
      _$this._folds ??= ListBuilder<EntityFold>();
  set folds(ListBuilder<EntityFold>? folds) => _$this._folds = folds;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  EntityFoldPageBuilder() {
    EntityFoldPage._defaults(this);
  }

  EntityFoldPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _folds = $v.folds.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EntityFoldPage other) {
    _$v = other as _$EntityFoldPage;
  }

  @override
  void update(void Function(EntityFoldPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EntityFoldPage build() => _build();

  _$EntityFoldPage _build() {
    _$EntityFoldPage _$result;
    try {
      _$result =
          _$v ??
          _$EntityFoldPage._(folds: folds.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'folds';
        folds.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EntityFoldPage',
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
