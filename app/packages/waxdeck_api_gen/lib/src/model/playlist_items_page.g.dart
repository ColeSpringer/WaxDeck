// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_items_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaylistItemsPage extends PlaylistItemsPage {
  @override
  final BuiltList<PlaylistEntry> entries;
  @override
  final String? nextCursor;

  factory _$PlaylistItemsPage([
    void Function(PlaylistItemsPageBuilder)? updates,
  ]) => (PlaylistItemsPageBuilder()..update(updates))._build();

  _$PlaylistItemsPage._({required this.entries, this.nextCursor}) : super._();
  @override
  PlaylistItemsPage rebuild(void Function(PlaylistItemsPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlaylistItemsPageBuilder toBuilder() =>
      PlaylistItemsPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistItemsPage &&
        entries == other.entries &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistItemsPage')
          ..add('entries', entries)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class PlaylistItemsPageBuilder
    implements Builder<PlaylistItemsPage, PlaylistItemsPageBuilder> {
  _$PlaylistItemsPage? _$v;

  ListBuilder<PlaylistEntry>? _entries;
  ListBuilder<PlaylistEntry> get entries =>
      _$this._entries ??= ListBuilder<PlaylistEntry>();
  set entries(ListBuilder<PlaylistEntry>? entries) => _$this._entries = entries;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  PlaylistItemsPageBuilder() {
    PlaylistItemsPage._defaults(this);
  }

  PlaylistItemsPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entries = $v.entries.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistItemsPage other) {
    _$v = other as _$PlaylistItemsPage;
  }

  @override
  void update(void Function(PlaylistItemsPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistItemsPage build() => _build();

  _$PlaylistItemsPage _build() {
    _$PlaylistItemsPage _$result;
    try {
      _$result =
          _$v ??
          _$PlaylistItemsPage._(
            entries: entries.build(),
            nextCursor: nextCursor,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaylistItemsPage',
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
