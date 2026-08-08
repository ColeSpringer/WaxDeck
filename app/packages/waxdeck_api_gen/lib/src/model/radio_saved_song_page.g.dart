// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radio_saved_song_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RadioSavedSongPage extends RadioSavedSongPage {
  @override
  final BuiltList<RadioSavedSong> songs;
  @override
  final String? nextCursor;

  factory _$RadioSavedSongPage([
    void Function(RadioSavedSongPageBuilder)? updates,
  ]) => (RadioSavedSongPageBuilder()..update(updates))._build();

  _$RadioSavedSongPage._({required this.songs, this.nextCursor}) : super._();
  @override
  RadioSavedSongPage rebuild(
    void Function(RadioSavedSongPageBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  RadioSavedSongPageBuilder toBuilder() =>
      RadioSavedSongPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RadioSavedSongPage &&
        songs == other.songs &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, songs.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RadioSavedSongPage')
          ..add('songs', songs)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class RadioSavedSongPageBuilder
    implements Builder<RadioSavedSongPage, RadioSavedSongPageBuilder> {
  _$RadioSavedSongPage? _$v;

  ListBuilder<RadioSavedSong>? _songs;
  ListBuilder<RadioSavedSong> get songs =>
      _$this._songs ??= ListBuilder<RadioSavedSong>();
  set songs(ListBuilder<RadioSavedSong>? songs) => _$this._songs = songs;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  RadioSavedSongPageBuilder() {
    RadioSavedSongPage._defaults(this);
  }

  RadioSavedSongPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _songs = $v.songs.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RadioSavedSongPage other) {
    _$v = other as _$RadioSavedSongPage;
  }

  @override
  void update(void Function(RadioSavedSongPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RadioSavedSongPage build() => _build();

  _$RadioSavedSongPage _build() {
    _$RadioSavedSongPage _$result;
    try {
      _$result =
          _$v ??
          _$RadioSavedSongPage._(songs: songs.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'songs';
        songs.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'RadioSavedSongPage',
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
