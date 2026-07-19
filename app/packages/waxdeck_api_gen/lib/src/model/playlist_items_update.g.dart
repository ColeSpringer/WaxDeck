// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_items_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaylistItemsUpdate extends PlaylistItemsUpdate {
  @override
  final BuiltList<String> itemPids;
  @override
  final DateTime? baseUpdatedAt;

  factory _$PlaylistItemsUpdate([
    void Function(PlaylistItemsUpdateBuilder)? updates,
  ]) => (PlaylistItemsUpdateBuilder()..update(updates))._build();

  _$PlaylistItemsUpdate._({required this.itemPids, this.baseUpdatedAt})
    : super._();
  @override
  PlaylistItemsUpdate rebuild(
    void Function(PlaylistItemsUpdateBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaylistItemsUpdateBuilder toBuilder() =>
      PlaylistItemsUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistItemsUpdate &&
        itemPids == other.itemPids &&
        baseUpdatedAt == other.baseUpdatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, itemPids.hashCode);
    _$hash = $jc(_$hash, baseUpdatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistItemsUpdate')
          ..add('itemPids', itemPids)
          ..add('baseUpdatedAt', baseUpdatedAt))
        .toString();
  }
}

class PlaylistItemsUpdateBuilder
    implements Builder<PlaylistItemsUpdate, PlaylistItemsUpdateBuilder> {
  _$PlaylistItemsUpdate? _$v;

  ListBuilder<String>? _itemPids;
  ListBuilder<String> get itemPids =>
      _$this._itemPids ??= ListBuilder<String>();
  set itemPids(ListBuilder<String>? itemPids) => _$this._itemPids = itemPids;

  DateTime? _baseUpdatedAt;
  DateTime? get baseUpdatedAt => _$this._baseUpdatedAt;
  set baseUpdatedAt(DateTime? baseUpdatedAt) =>
      _$this._baseUpdatedAt = baseUpdatedAt;

  PlaylistItemsUpdateBuilder() {
    PlaylistItemsUpdate._defaults(this);
  }

  PlaylistItemsUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _itemPids = $v.itemPids.toBuilder();
      _baseUpdatedAt = $v.baseUpdatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistItemsUpdate other) {
    _$v = other as _$PlaylistItemsUpdate;
  }

  @override
  void update(void Function(PlaylistItemsUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistItemsUpdate build() => _build();

  _$PlaylistItemsUpdate _build() {
    _$PlaylistItemsUpdate _$result;
    try {
      _$result =
          _$v ??
          _$PlaylistItemsUpdate._(
            itemPids: itemPids.build(),
            baseUpdatedAt: baseUpdatedAt,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'itemPids';
        itemPids.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaylistItemsUpdate',
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
