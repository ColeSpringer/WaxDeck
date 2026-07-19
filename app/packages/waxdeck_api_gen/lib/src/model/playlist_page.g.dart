// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaylistPage extends PlaylistPage {
  @override
  final BuiltList<Playlist> playlists;
  @override
  final String? nextCursor;

  factory _$PlaylistPage([void Function(PlaylistPageBuilder)? updates]) =>
      (PlaylistPageBuilder()..update(updates))._build();

  _$PlaylistPage._({required this.playlists, this.nextCursor}) : super._();
  @override
  PlaylistPage rebuild(void Function(PlaylistPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlaylistPageBuilder toBuilder() => PlaylistPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistPage &&
        playlists == other.playlists &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, playlists.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistPage')
          ..add('playlists', playlists)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class PlaylistPageBuilder
    implements Builder<PlaylistPage, PlaylistPageBuilder> {
  _$PlaylistPage? _$v;

  ListBuilder<Playlist>? _playlists;
  ListBuilder<Playlist> get playlists =>
      _$this._playlists ??= ListBuilder<Playlist>();
  set playlists(ListBuilder<Playlist>? playlists) =>
      _$this._playlists = playlists;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  PlaylistPageBuilder() {
    PlaylistPage._defaults(this);
  }

  PlaylistPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _playlists = $v.playlists.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistPage other) {
    _$v = other as _$PlaylistPage;
  }

  @override
  void update(void Function(PlaylistPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistPage build() => _build();

  _$PlaylistPage _build() {
    _$PlaylistPage _$result;
    try {
      _$result =
          _$v ??
          _$PlaylistPage._(
            playlists: playlists.build(),
            nextCursor: nextCursor,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'playlists';
        playlists.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaylistPage',
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
