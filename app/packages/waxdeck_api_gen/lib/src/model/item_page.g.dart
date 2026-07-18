// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ItemPage extends ItemPage {
  @override
  final BuiltList<ItemSummary> items;
  @override
  final String? nextCursor;
  @override
  final int? seed;

  factory _$ItemPage([void Function(ItemPageBuilder)? updates]) =>
      (ItemPageBuilder()..update(updates))._build();

  _$ItemPage._({required this.items, this.nextCursor, this.seed}) : super._();
  @override
  ItemPage rebuild(void Function(ItemPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ItemPageBuilder toBuilder() => ItemPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ItemPage &&
        items == other.items &&
        nextCursor == other.nextCursor &&
        seed == other.seed;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jc(_$hash, seed.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ItemPage')
          ..add('items', items)
          ..add('nextCursor', nextCursor)
          ..add('seed', seed))
        .toString();
  }
}

class ItemPageBuilder implements Builder<ItemPage, ItemPageBuilder> {
  _$ItemPage? _$v;

  ListBuilder<ItemSummary>? _items;
  ListBuilder<ItemSummary> get items =>
      _$this._items ??= ListBuilder<ItemSummary>();
  set items(ListBuilder<ItemSummary>? items) => _$this._items = items;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  int? _seed;
  int? get seed => _$this._seed;
  set seed(int? seed) => _$this._seed = seed;

  ItemPageBuilder() {
    ItemPage._defaults(this);
  }

  ItemPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items.toBuilder();
      _nextCursor = $v.nextCursor;
      _seed = $v.seed;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ItemPage other) {
    _$v = other as _$ItemPage;
  }

  @override
  void update(void Function(ItemPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ItemPage build() => _build();

  _$ItemPage _build() {
    _$ItemPage _$result;
    try {
      _$result =
          _$v ??
          _$ItemPage._(
            items: items.build(),
            nextCursor: nextCursor,
            seed: seed,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ItemPage',
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
