// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'm3u_import_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$M3uImportResult extends M3uImportResult {
  @override
  final Playlist playlist;
  @override
  final int matched;
  @override
  final int unmatched;
  @override
  final BuiltList<String>? unmatchedPaths;

  factory _$M3uImportResult([void Function(M3uImportResultBuilder)? updates]) =>
      (M3uImportResultBuilder()..update(updates))._build();

  _$M3uImportResult._({
    required this.playlist,
    required this.matched,
    required this.unmatched,
    this.unmatchedPaths,
  }) : super._();
  @override
  M3uImportResult rebuild(void Function(M3uImportResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  M3uImportResultBuilder toBuilder() => M3uImportResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is M3uImportResult &&
        playlist == other.playlist &&
        matched == other.matched &&
        unmatched == other.unmatched &&
        unmatchedPaths == other.unmatchedPaths;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, playlist.hashCode);
    _$hash = $jc(_$hash, matched.hashCode);
    _$hash = $jc(_$hash, unmatched.hashCode);
    _$hash = $jc(_$hash, unmatchedPaths.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'M3uImportResult')
          ..add('playlist', playlist)
          ..add('matched', matched)
          ..add('unmatched', unmatched)
          ..add('unmatchedPaths', unmatchedPaths))
        .toString();
  }
}

class M3uImportResultBuilder
    implements Builder<M3uImportResult, M3uImportResultBuilder> {
  _$M3uImportResult? _$v;

  PlaylistBuilder? _playlist;
  PlaylistBuilder get playlist => _$this._playlist ??= PlaylistBuilder();
  set playlist(PlaylistBuilder? playlist) => _$this._playlist = playlist;

  int? _matched;
  int? get matched => _$this._matched;
  set matched(int? matched) => _$this._matched = matched;

  int? _unmatched;
  int? get unmatched => _$this._unmatched;
  set unmatched(int? unmatched) => _$this._unmatched = unmatched;

  ListBuilder<String>? _unmatchedPaths;
  ListBuilder<String> get unmatchedPaths =>
      _$this._unmatchedPaths ??= ListBuilder<String>();
  set unmatchedPaths(ListBuilder<String>? unmatchedPaths) =>
      _$this._unmatchedPaths = unmatchedPaths;

  M3uImportResultBuilder() {
    M3uImportResult._defaults(this);
  }

  M3uImportResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _playlist = $v.playlist.toBuilder();
      _matched = $v.matched;
      _unmatched = $v.unmatched;
      _unmatchedPaths = $v.unmatchedPaths?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(M3uImportResult other) {
    _$v = other as _$M3uImportResult;
  }

  @override
  void update(void Function(M3uImportResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  M3uImportResult build() => _build();

  _$M3uImportResult _build() {
    _$M3uImportResult _$result;
    try {
      _$result =
          _$v ??
          _$M3uImportResult._(
            playlist: playlist.build(),
            matched: BuiltValueNullFieldError.checkNotNull(
              matched,
              r'M3uImportResult',
              'matched',
            ),
            unmatched: BuiltValueNullFieldError.checkNotNull(
              unmatched,
              r'M3uImportResult',
              'unmatched',
            ),
            unmatchedPaths: _unmatchedPaths?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'playlist';
        playlist.build();

        _$failedField = 'unmatchedPaths';
        _unmatchedPaths?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'M3uImportResult',
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
