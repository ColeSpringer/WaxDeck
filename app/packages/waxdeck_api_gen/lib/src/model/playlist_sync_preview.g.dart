// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_sync_preview.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaylistSyncPreview extends PlaylistSyncPreview {
  @override
  final int entries;
  @override
  final int wouldAdd;
  @override
  final int wouldDownload;
  @override
  final int wouldRemove;
  @override
  final int wouldTrash;
  @override
  final int pending;
  @override
  final int unavailable;
  @override
  final int missing;
  @override
  final BuiltList<PlaylistImportMiss>? misses;

  factory _$PlaylistSyncPreview([
    void Function(PlaylistSyncPreviewBuilder)? updates,
  ]) => (PlaylistSyncPreviewBuilder()..update(updates))._build();

  _$PlaylistSyncPreview._({
    required this.entries,
    required this.wouldAdd,
    required this.wouldDownload,
    required this.wouldRemove,
    required this.wouldTrash,
    required this.pending,
    required this.unavailable,
    required this.missing,
    this.misses,
  }) : super._();
  @override
  PlaylistSyncPreview rebuild(
    void Function(PlaylistSyncPreviewBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaylistSyncPreviewBuilder toBuilder() =>
      PlaylistSyncPreviewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistSyncPreview &&
        entries == other.entries &&
        wouldAdd == other.wouldAdd &&
        wouldDownload == other.wouldDownload &&
        wouldRemove == other.wouldRemove &&
        wouldTrash == other.wouldTrash &&
        pending == other.pending &&
        unavailable == other.unavailable &&
        missing == other.missing &&
        misses == other.misses;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jc(_$hash, wouldAdd.hashCode);
    _$hash = $jc(_$hash, wouldDownload.hashCode);
    _$hash = $jc(_$hash, wouldRemove.hashCode);
    _$hash = $jc(_$hash, wouldTrash.hashCode);
    _$hash = $jc(_$hash, pending.hashCode);
    _$hash = $jc(_$hash, unavailable.hashCode);
    _$hash = $jc(_$hash, missing.hashCode);
    _$hash = $jc(_$hash, misses.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistSyncPreview')
          ..add('entries', entries)
          ..add('wouldAdd', wouldAdd)
          ..add('wouldDownload', wouldDownload)
          ..add('wouldRemove', wouldRemove)
          ..add('wouldTrash', wouldTrash)
          ..add('pending', pending)
          ..add('unavailable', unavailable)
          ..add('missing', missing)
          ..add('misses', misses))
        .toString();
  }
}

class PlaylistSyncPreviewBuilder
    implements Builder<PlaylistSyncPreview, PlaylistSyncPreviewBuilder> {
  _$PlaylistSyncPreview? _$v;

  int? _entries;
  int? get entries => _$this._entries;
  set entries(int? entries) => _$this._entries = entries;

  int? _wouldAdd;
  int? get wouldAdd => _$this._wouldAdd;
  set wouldAdd(int? wouldAdd) => _$this._wouldAdd = wouldAdd;

  int? _wouldDownload;
  int? get wouldDownload => _$this._wouldDownload;
  set wouldDownload(int? wouldDownload) =>
      _$this._wouldDownload = wouldDownload;

  int? _wouldRemove;
  int? get wouldRemove => _$this._wouldRemove;
  set wouldRemove(int? wouldRemove) => _$this._wouldRemove = wouldRemove;

  int? _wouldTrash;
  int? get wouldTrash => _$this._wouldTrash;
  set wouldTrash(int? wouldTrash) => _$this._wouldTrash = wouldTrash;

  int? _pending;
  int? get pending => _$this._pending;
  set pending(int? pending) => _$this._pending = pending;

  int? _unavailable;
  int? get unavailable => _$this._unavailable;
  set unavailable(int? unavailable) => _$this._unavailable = unavailable;

  int? _missing;
  int? get missing => _$this._missing;
  set missing(int? missing) => _$this._missing = missing;

  ListBuilder<PlaylistImportMiss>? _misses;
  ListBuilder<PlaylistImportMiss> get misses =>
      _$this._misses ??= ListBuilder<PlaylistImportMiss>();
  set misses(ListBuilder<PlaylistImportMiss>? misses) =>
      _$this._misses = misses;

  PlaylistSyncPreviewBuilder() {
    PlaylistSyncPreview._defaults(this);
  }

  PlaylistSyncPreviewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entries = $v.entries;
      _wouldAdd = $v.wouldAdd;
      _wouldDownload = $v.wouldDownload;
      _wouldRemove = $v.wouldRemove;
      _wouldTrash = $v.wouldTrash;
      _pending = $v.pending;
      _unavailable = $v.unavailable;
      _missing = $v.missing;
      _misses = $v.misses?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistSyncPreview other) {
    _$v = other as _$PlaylistSyncPreview;
  }

  @override
  void update(void Function(PlaylistSyncPreviewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistSyncPreview build() => _build();

  _$PlaylistSyncPreview _build() {
    _$PlaylistSyncPreview _$result;
    try {
      _$result =
          _$v ??
          _$PlaylistSyncPreview._(
            entries: BuiltValueNullFieldError.checkNotNull(
              entries,
              r'PlaylistSyncPreview',
              'entries',
            ),
            wouldAdd: BuiltValueNullFieldError.checkNotNull(
              wouldAdd,
              r'PlaylistSyncPreview',
              'wouldAdd',
            ),
            wouldDownload: BuiltValueNullFieldError.checkNotNull(
              wouldDownload,
              r'PlaylistSyncPreview',
              'wouldDownload',
            ),
            wouldRemove: BuiltValueNullFieldError.checkNotNull(
              wouldRemove,
              r'PlaylistSyncPreview',
              'wouldRemove',
            ),
            wouldTrash: BuiltValueNullFieldError.checkNotNull(
              wouldTrash,
              r'PlaylistSyncPreview',
              'wouldTrash',
            ),
            pending: BuiltValueNullFieldError.checkNotNull(
              pending,
              r'PlaylistSyncPreview',
              'pending',
            ),
            unavailable: BuiltValueNullFieldError.checkNotNull(
              unavailable,
              r'PlaylistSyncPreview',
              'unavailable',
            ),
            missing: BuiltValueNullFieldError.checkNotNull(
              missing,
              r'PlaylistSyncPreview',
              'missing',
            ),
            misses: _misses?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'misses';
        _misses?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'PlaylistSyncPreview',
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
