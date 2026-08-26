// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_sync_counts.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlaylistSyncCounts extends PlaylistSyncCounts {
  @override
  final int added;
  @override
  final int removed;
  @override
  final int trashed;
  @override
  final int queued;
  @override
  final int unavailable;
  @override
  final int missing;

  factory _$PlaylistSyncCounts([
    void Function(PlaylistSyncCountsBuilder)? updates,
  ]) => (PlaylistSyncCountsBuilder()..update(updates))._build();

  _$PlaylistSyncCounts._({
    required this.added,
    required this.removed,
    required this.trashed,
    required this.queued,
    required this.unavailable,
    required this.missing,
  }) : super._();
  @override
  PlaylistSyncCounts rebuild(
    void Function(PlaylistSyncCountsBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  PlaylistSyncCountsBuilder toBuilder() =>
      PlaylistSyncCountsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlaylistSyncCounts &&
        added == other.added &&
        removed == other.removed &&
        trashed == other.trashed &&
        queued == other.queued &&
        unavailable == other.unavailable &&
        missing == other.missing;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, added.hashCode);
    _$hash = $jc(_$hash, removed.hashCode);
    _$hash = $jc(_$hash, trashed.hashCode);
    _$hash = $jc(_$hash, queued.hashCode);
    _$hash = $jc(_$hash, unavailable.hashCode);
    _$hash = $jc(_$hash, missing.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlaylistSyncCounts')
          ..add('added', added)
          ..add('removed', removed)
          ..add('trashed', trashed)
          ..add('queued', queued)
          ..add('unavailable', unavailable)
          ..add('missing', missing))
        .toString();
  }
}

class PlaylistSyncCountsBuilder
    implements Builder<PlaylistSyncCounts, PlaylistSyncCountsBuilder> {
  _$PlaylistSyncCounts? _$v;

  int? _added;
  int? get added => _$this._added;
  set added(int? added) => _$this._added = added;

  int? _removed;
  int? get removed => _$this._removed;
  set removed(int? removed) => _$this._removed = removed;

  int? _trashed;
  int? get trashed => _$this._trashed;
  set trashed(int? trashed) => _$this._trashed = trashed;

  int? _queued;
  int? get queued => _$this._queued;
  set queued(int? queued) => _$this._queued = queued;

  int? _unavailable;
  int? get unavailable => _$this._unavailable;
  set unavailable(int? unavailable) => _$this._unavailable = unavailable;

  int? _missing;
  int? get missing => _$this._missing;
  set missing(int? missing) => _$this._missing = missing;

  PlaylistSyncCountsBuilder() {
    PlaylistSyncCounts._defaults(this);
  }

  PlaylistSyncCountsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _added = $v.added;
      _removed = $v.removed;
      _trashed = $v.trashed;
      _queued = $v.queued;
      _unavailable = $v.unavailable;
      _missing = $v.missing;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlaylistSyncCounts other) {
    _$v = other as _$PlaylistSyncCounts;
  }

  @override
  void update(void Function(PlaylistSyncCountsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlaylistSyncCounts build() => _build();

  _$PlaylistSyncCounts _build() {
    final _$result =
        _$v ??
        _$PlaylistSyncCounts._(
          added: BuiltValueNullFieldError.checkNotNull(
            added,
            r'PlaylistSyncCounts',
            'added',
          ),
          removed: BuiltValueNullFieldError.checkNotNull(
            removed,
            r'PlaylistSyncCounts',
            'removed',
          ),
          trashed: BuiltValueNullFieldError.checkNotNull(
            trashed,
            r'PlaylistSyncCounts',
            'trashed',
          ),
          queued: BuiltValueNullFieldError.checkNotNull(
            queued,
            r'PlaylistSyncCounts',
            'queued',
          ),
          unavailable: BuiltValueNullFieldError.checkNotNull(
            unavailable,
            r'PlaylistSyncCounts',
            'unavailable',
          ),
          missing: BuiltValueNullFieldError.checkNotNull(
            missing,
            r'PlaylistSyncCounts',
            'missing',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
