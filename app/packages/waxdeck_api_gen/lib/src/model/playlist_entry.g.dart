// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaylistEntry extends PlaylistEntry {
  @override
  final int? position;
  @override
  final ItemSummary item;

  factory _$PlaylistEntry([void Function(PlaylistEntryBuilder)? updates]) =>
      (PlaylistEntryBuilder()..update(updates))._build();

  _$PlaylistEntry._({this.position, required this.item}) : super._();
  @override
  PlaylistEntry rebuild(void Function(PlaylistEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlaylistEntryBuilder toBuilder() => PlaylistEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistEntry &&
        position == other.position &&
        item == other.item;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, position.hashCode);
    _$hash = $jc(_$hash, item.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistEntry')
          ..add('position', position)
          ..add('item', item))
        .toString();
  }
}

class PlaylistEntryBuilder
    implements Builder<PlaylistEntry, PlaylistEntryBuilder> {
  _$PlaylistEntry? _$v;

  int? _position;
  int? get position => _$this._position;
  set position(int? position) => _$this._position = position;

  ItemSummary? _item;
  ItemSummary? get item => _$this._item;
  set item(ItemSummary? item) => _$this._item = item;

  PlaylistEntryBuilder() {
    PlaylistEntry._defaults(this);
  }

  PlaylistEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _position = $v.position;
      _item = $v.item;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistEntry other) {
    _$v = other as _$PlaylistEntry;
  }

  @override
  void update(void Function(PlaylistEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistEntry build() => _build();

  _$PlaylistEntry _build() {
    final _$result =
        _$v ??
        _$PlaylistEntry._(
          position: position,
          item: BuiltValueNullFieldError.checkNotNull(
            item,
            r'PlaylistEntry',
            'item',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
