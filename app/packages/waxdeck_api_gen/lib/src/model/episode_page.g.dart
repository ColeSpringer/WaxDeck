// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'episode_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EpisodePage extends EpisodePage {
  @override
  final BuiltList<EpisodeSummary> items;
  @override
  final String? nextCursor;

  factory _$EpisodePage([void Function(EpisodePageBuilder)? updates]) =>
      (EpisodePageBuilder()..update(updates))._build();

  _$EpisodePage._({required this.items, this.nextCursor}) : super._();
  @override
  EpisodePage rebuild(void Function(EpisodePageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EpisodePageBuilder toBuilder() => EpisodePageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EpisodePage &&
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
    return (newBuiltValueToStringHelper(r'EpisodePage')
          ..add('items', items)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class EpisodePageBuilder implements Builder<EpisodePage, EpisodePageBuilder> {
  _$EpisodePage? _$v;

  ListBuilder<EpisodeSummary>? _items;
  ListBuilder<EpisodeSummary> get items =>
      _$this._items ??= ListBuilder<EpisodeSummary>();
  set items(ListBuilder<EpisodeSummary>? items) => _$this._items = items;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  EpisodePageBuilder() {
    EpisodePage._defaults(this);
  }

  EpisodePageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EpisodePage other) {
    _$v = other as _$EpisodePage;
  }

  @override
  void update(void Function(EpisodePageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EpisodePage build() => _build();

  _$EpisodePage _build() {
    _$EpisodePage _$result;
    try {
      _$result =
          _$v ?? _$EpisodePage._(items: items.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'EpisodePage',
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
