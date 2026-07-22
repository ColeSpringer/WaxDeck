// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instant_mix.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InstantMix extends InstantMix {
  @override
  final MixBasis basis;
  @override
  final BuiltList<ItemSummary> items;

  factory _$InstantMix([void Function(InstantMixBuilder)? updates]) =>
      (InstantMixBuilder()..update(updates))._build();

  _$InstantMix._({required this.basis, required this.items}) : super._();
  @override
  InstantMix rebuild(void Function(InstantMixBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InstantMixBuilder toBuilder() => InstantMixBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InstantMix && basis == other.basis && items == other.items;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, basis.hashCode);
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'InstantMix')
          ..add('basis', basis)
          ..add('items', items))
        .toString();
  }
}

class InstantMixBuilder implements Builder<InstantMix, InstantMixBuilder> {
  _$InstantMix? _$v;

  MixBasis? _basis;
  MixBasis? get basis => _$this._basis;
  set basis(MixBasis? basis) => _$this._basis = basis;

  ListBuilder<ItemSummary>? _items;
  ListBuilder<ItemSummary> get items =>
      _$this._items ??= ListBuilder<ItemSummary>();
  set items(ListBuilder<ItemSummary>? items) => _$this._items = items;

  InstantMixBuilder() {
    InstantMix._defaults(this);
  }

  InstantMixBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _basis = $v.basis;
      _items = $v.items.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(InstantMix other) {
    _$v = other as _$InstantMix;
  }

  @override
  void update(void Function(InstantMixBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InstantMix build() => _build();

  _$InstantMix _build() {
    _$InstantMix _$result;
    try {
      _$result =
          _$v ??
          _$InstantMix._(
            basis: BuiltValueNullFieldError.checkNotNull(
              basis,
              r'InstantMix',
              'basis',
            ),
            items: items.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'InstantMix',
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
