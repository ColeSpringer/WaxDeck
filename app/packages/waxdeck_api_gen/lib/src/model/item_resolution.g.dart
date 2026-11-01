// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item_resolution.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ItemResolution extends ItemResolution {
  @override
  final BuiltList<ItemSummary> items;
  @override
  final BuiltList<String>? departed;

  factory _$ItemResolution([void Function(ItemResolutionBuilder)? updates]) =>
      (ItemResolutionBuilder()..update(updates))._build();

  _$ItemResolution._({required this.items, this.departed}) : super._();
  @override
  ItemResolution rebuild(void Function(ItemResolutionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ItemResolutionBuilder toBuilder() => ItemResolutionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ItemResolution &&
        items == other.items &&
        departed == other.departed;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jc(_$hash, departed.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ItemResolution')
          ..add('items', items)
          ..add('departed', departed))
        .toString();
  }
}

class ItemResolutionBuilder
    implements Builder<ItemResolution, ItemResolutionBuilder> {
  _$ItemResolution? _$v;

  ListBuilder<ItemSummary>? _items;
  ListBuilder<ItemSummary> get items =>
      _$this._items ??= ListBuilder<ItemSummary>();
  set items(ListBuilder<ItemSummary>? items) => _$this._items = items;

  ListBuilder<String>? _departed;
  ListBuilder<String> get departed =>
      _$this._departed ??= ListBuilder<String>();
  set departed(ListBuilder<String>? departed) => _$this._departed = departed;

  ItemResolutionBuilder() {
    ItemResolution._defaults(this);
  }

  ItemResolutionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items.toBuilder();
      _departed = $v.departed?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ItemResolution other) {
    _$v = other as _$ItemResolution;
  }

  @override
  void update(void Function(ItemResolutionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ItemResolution build() => _build();

  _$ItemResolution _build() {
    _$ItemResolution _$result;
    try {
      _$result =
          _$v ??
          _$ItemResolution._(
            items: items.build(),
            departed: _departed?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
        _$failedField = 'departed';
        _departed?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ItemResolution',
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
