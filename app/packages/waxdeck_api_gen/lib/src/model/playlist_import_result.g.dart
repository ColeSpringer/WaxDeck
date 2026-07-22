// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_import_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaylistImportResult extends PlaylistImportResult {
  @override
  final String? playlistPid;
  @override
  final String name;
  @override
  final int requested;
  @override
  final int resolved;
  @override
  final BuiltList<PlaylistImportMiss> missing;
  @override
  final ResolveRungCounts rungs;

  factory _$PlaylistImportResult([
    void Function(PlaylistImportResultBuilder)? updates,
  ]) => (PlaylistImportResultBuilder()..update(updates))._build();

  _$PlaylistImportResult._({
    this.playlistPid,
    required this.name,
    required this.requested,
    required this.resolved,
    required this.missing,
    required this.rungs,
  }) : super._();
  @override
  PlaylistImportResult rebuild(
    void Function(PlaylistImportResultBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaylistImportResultBuilder toBuilder() =>
      PlaylistImportResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistImportResult &&
        playlistPid == other.playlistPid &&
        name == other.name &&
        requested == other.requested &&
        resolved == other.resolved &&
        missing == other.missing &&
        rungs == other.rungs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, playlistPid.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, requested.hashCode);
    _$hash = $jc(_$hash, resolved.hashCode);
    _$hash = $jc(_$hash, missing.hashCode);
    _$hash = $jc(_$hash, rungs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistImportResult')
          ..add('playlistPid', playlistPid)
          ..add('name', name)
          ..add('requested', requested)
          ..add('resolved', resolved)
          ..add('missing', missing)
          ..add('rungs', rungs))
        .toString();
  }
}

class PlaylistImportResultBuilder
    implements Builder<PlaylistImportResult, PlaylistImportResultBuilder> {
  _$PlaylistImportResult? _$v;

  String? _playlistPid;
  String? get playlistPid => _$this._playlistPid;
  set playlistPid(String? playlistPid) => _$this._playlistPid = playlistPid;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _requested;
  int? get requested => _$this._requested;
  set requested(int? requested) => _$this._requested = requested;

  int? _resolved;
  int? get resolved => _$this._resolved;
  set resolved(int? resolved) => _$this._resolved = resolved;

  ListBuilder<PlaylistImportMiss>? _missing;
  ListBuilder<PlaylistImportMiss> get missing =>
      _$this._missing ??= ListBuilder<PlaylistImportMiss>();
  set missing(ListBuilder<PlaylistImportMiss>? missing) =>
      _$this._missing = missing;

  ResolveRungCountsBuilder? _rungs;
  ResolveRungCountsBuilder get rungs =>
      _$this._rungs ??= ResolveRungCountsBuilder();
  set rungs(ResolveRungCountsBuilder? rungs) => _$this._rungs = rungs;

  PlaylistImportResultBuilder() {
    PlaylistImportResult._defaults(this);
  }

  PlaylistImportResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _playlistPid = $v.playlistPid;
      _name = $v.name;
      _requested = $v.requested;
      _resolved = $v.resolved;
      _missing = $v.missing.toBuilder();
      _rungs = $v.rungs.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistImportResult other) {
    _$v = other as _$PlaylistImportResult;
  }

  @override
  void update(void Function(PlaylistImportResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistImportResult build() => _build();

  _$PlaylistImportResult _build() {
    _$PlaylistImportResult _$result;
    try {
      _$result =
          _$v ??
          _$PlaylistImportResult._(
            playlistPid: playlistPid,
            name: BuiltValueNullFieldError.checkNotNull(
              name,
              r'PlaylistImportResult',
              'name',
            ),
            requested: BuiltValueNullFieldError.checkNotNull(
              requested,
              r'PlaylistImportResult',
              'requested',
            ),
            resolved: BuiltValueNullFieldError.checkNotNull(
              resolved,
              r'PlaylistImportResult',
              'resolved',
            ),
            missing: missing.build(),
            rungs: rungs.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'missing';
        missing.build();
        _$failedField = 'rungs';
        rungs.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaylistImportResult',
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
