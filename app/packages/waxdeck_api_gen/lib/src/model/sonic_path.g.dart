// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sonic_path.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SonicPath extends SonicPath {
  @override
  final bool complete;
  @override
  final BuiltList<ItemSummary> items;

  factory _$SonicPath([void Function(SonicPathBuilder)? updates]) =>
      (SonicPathBuilder()..update(updates))._build();

  _$SonicPath._({required this.complete, required this.items}) : super._();
  @override
  SonicPath rebuild(void Function(SonicPathBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SonicPathBuilder toBuilder() => SonicPathBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SonicPath &&
        complete == other.complete &&
        items == other.items;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, complete.hashCode);
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SonicPath')
          ..add('complete', complete)
          ..add('items', items))
        .toString();
  }
}

class SonicPathBuilder implements Builder<SonicPath, SonicPathBuilder> {
  _$SonicPath? _$v;

  bool? _complete;
  bool? get complete => _$this._complete;
  set complete(bool? complete) => _$this._complete = complete;

  ListBuilder<ItemSummary>? _items;
  ListBuilder<ItemSummary> get items =>
      _$this._items ??= ListBuilder<ItemSummary>();
  set items(ListBuilder<ItemSummary>? items) => _$this._items = items;

  SonicPathBuilder() {
    SonicPath._defaults(this);
  }

  SonicPathBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _complete = $v.complete;
      _items = $v.items.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SonicPath other) {
    _$v = other as _$SonicPath;
  }

  @override
  void update(void Function(SonicPathBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SonicPath build() => _build();

  _$SonicPath _build() {
    _$SonicPath _$result;
    try {
      _$result =
          _$v ??
          _$SonicPath._(
            complete: BuiltValueNullFieldError.checkNotNull(
              complete,
              r'SonicPath',
              'complete',
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
          r'SonicPath',
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
