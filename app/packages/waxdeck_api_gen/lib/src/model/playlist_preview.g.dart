// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_preview.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaylistPreview extends PlaylistPreview {
  @override
  final BuiltList<ItemSummary> items;
  @override
  final int total;

  factory _$PlaylistPreview([void Function(PlaylistPreviewBuilder)? updates]) =>
      (PlaylistPreviewBuilder()..update(updates))._build();

  _$PlaylistPreview._({required this.items, required this.total}) : super._();
  @override
  PlaylistPreview rebuild(void Function(PlaylistPreviewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlaylistPreviewBuilder toBuilder() => PlaylistPreviewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistPreview &&
        items == other.items &&
        total == other.total;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jc(_$hash, total.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistPreview')
          ..add('items', items)
          ..add('total', total))
        .toString();
  }
}

class PlaylistPreviewBuilder
    implements Builder<PlaylistPreview, PlaylistPreviewBuilder> {
  _$PlaylistPreview? _$v;

  ListBuilder<ItemSummary>? _items;
  ListBuilder<ItemSummary> get items =>
      _$this._items ??= ListBuilder<ItemSummary>();
  set items(ListBuilder<ItemSummary>? items) => _$this._items = items;

  int? _total;
  int? get total => _$this._total;
  set total(int? total) => _$this._total = total;

  PlaylistPreviewBuilder() {
    PlaylistPreview._defaults(this);
  }

  PlaylistPreviewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _items = $v.items.toBuilder();
      _total = $v.total;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistPreview other) {
    _$v = other as _$PlaylistPreview;
  }

  @override
  void update(void Function(PlaylistPreviewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistPreview build() => _build();

  _$PlaylistPreview _build() {
    _$PlaylistPreview _$result;
    try {
      _$result =
          _$v ??
          _$PlaylistPreview._(
            items: items.build(),
            total: BuiltValueNullFieldError.checkNotNull(
              total,
              r'PlaylistPreview',
              'total',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaylistPreview',
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
