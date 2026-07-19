// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subscription_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SubscriptionPage extends SubscriptionPage {
  @override
  final BuiltList<Subscription> items;
  @override
  final String? nextCursor;

  factory _$SubscriptionPage([
    void Function(SubscriptionPageBuilder)? updates,
  ]) => (SubscriptionPageBuilder()..update(updates))._build();

  _$SubscriptionPage._({required this.items, this.nextCursor}) : super._();
  @override
  SubscriptionPage rebuild(void Function(SubscriptionPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SubscriptionPageBuilder toBuilder() =>
      SubscriptionPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SubscriptionPage &&
        items == other.items &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SubscriptionPage')
          ..add('items', items)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class SubscriptionPageBuilder
    implements Builder<SubscriptionPage, SubscriptionPageBuilder> {
  _$SubscriptionPage? _$v;

  ListBuilder<Subscription>? _items;
  ListBuilder<Subscription> get items =>
      _$this._items ??= ListBuilder<Subscription>();
  set items(ListBuilder<Subscription>? items) => _$this._items = items;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  SubscriptionPageBuilder() {
    SubscriptionPage._defaults(this);
  }

  SubscriptionPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SubscriptionPage other) {
    _$v = other as _$SubscriptionPage;
  }

  @override
  void update(void Function(SubscriptionPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SubscriptionPage build() => _build();

  _$SubscriptionPage _build() {
    _$SubscriptionPage _$result;
    try {
      _$result =
          _$v ??
          _$SubscriptionPage._(items: items.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SubscriptionPage',
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
