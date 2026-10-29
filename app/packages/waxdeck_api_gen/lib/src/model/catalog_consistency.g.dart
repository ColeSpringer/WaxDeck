// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_consistency.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CatalogConsistency extends CatalogConsistency {
  @override
  final int itemsMissingFromSearch;
  @override
  final int orphanSearchRows;
  @override
  final int artistRollupDrift;
  @override
  final int genreRollupDrift;
  @override
  final int releaseGroupRollupDrift;
  @override
  final int sortKeyDrift;
  @override
  final int bookDurationDrift;
  @override
  final int bookIsbnKeyDrift;
  @override
  final int albumYearDrift;
  @override
  final int releaseYearDrift;
  @override
  final int playlistPositionDrift;
  @override
  final int orphanArtSources;
  @override
  final int orphanThumbnails;
  @override
  final int orphanTagProvenance;
  @override
  final int strandedTagRows;
  @override
  final bool consistent;
  @override
  final bool reclaimable;

  factory _$CatalogConsistency([
    void Function(CatalogConsistencyBuilder)? updates,
  ]) => (CatalogConsistencyBuilder()..update(updates))._build();

  _$CatalogConsistency._({
    required this.itemsMissingFromSearch,
    required this.orphanSearchRows,
    required this.artistRollupDrift,
    required this.genreRollupDrift,
    required this.releaseGroupRollupDrift,
    required this.sortKeyDrift,
    required this.bookDurationDrift,
    required this.bookIsbnKeyDrift,
    required this.albumYearDrift,
    required this.releaseYearDrift,
    required this.playlistPositionDrift,
    required this.orphanArtSources,
    required this.orphanThumbnails,
    required this.orphanTagProvenance,
    required this.strandedTagRows,
    required this.consistent,
    required this.reclaimable,
  }) : super._();
  @override
  CatalogConsistency rebuild(
    void Function(CatalogConsistencyBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  CatalogConsistencyBuilder toBuilder() =>
      CatalogConsistencyBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CatalogConsistency &&
        itemsMissingFromSearch == other.itemsMissingFromSearch &&
        orphanSearchRows == other.orphanSearchRows &&
        artistRollupDrift == other.artistRollupDrift &&
        genreRollupDrift == other.genreRollupDrift &&
        releaseGroupRollupDrift == other.releaseGroupRollupDrift &&
        sortKeyDrift == other.sortKeyDrift &&
        bookDurationDrift == other.bookDurationDrift &&
        bookIsbnKeyDrift == other.bookIsbnKeyDrift &&
        albumYearDrift == other.albumYearDrift &&
        releaseYearDrift == other.releaseYearDrift &&
        playlistPositionDrift == other.playlistPositionDrift &&
        orphanArtSources == other.orphanArtSources &&
        orphanThumbnails == other.orphanThumbnails &&
        orphanTagProvenance == other.orphanTagProvenance &&
        strandedTagRows == other.strandedTagRows &&
        consistent == other.consistent &&
        reclaimable == other.reclaimable;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, itemsMissingFromSearch.hashCode);
    _$hash = $jc(_$hash, orphanSearchRows.hashCode);
    _$hash = $jc(_$hash, artistRollupDrift.hashCode);
    _$hash = $jc(_$hash, genreRollupDrift.hashCode);
    _$hash = $jc(_$hash, releaseGroupRollupDrift.hashCode);
    _$hash = $jc(_$hash, sortKeyDrift.hashCode);
    _$hash = $jc(_$hash, bookDurationDrift.hashCode);
    _$hash = $jc(_$hash, bookIsbnKeyDrift.hashCode);
    _$hash = $jc(_$hash, albumYearDrift.hashCode);
    _$hash = $jc(_$hash, releaseYearDrift.hashCode);
    _$hash = $jc(_$hash, playlistPositionDrift.hashCode);
    _$hash = $jc(_$hash, orphanArtSources.hashCode);
    _$hash = $jc(_$hash, orphanThumbnails.hashCode);
    _$hash = $jc(_$hash, orphanTagProvenance.hashCode);
    _$hash = $jc(_$hash, strandedTagRows.hashCode);
    _$hash = $jc(_$hash, consistent.hashCode);
    _$hash = $jc(_$hash, reclaimable.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CatalogConsistency')
          ..add('itemsMissingFromSearch', itemsMissingFromSearch)
          ..add('orphanSearchRows', orphanSearchRows)
          ..add('artistRollupDrift', artistRollupDrift)
          ..add('genreRollupDrift', genreRollupDrift)
          ..add('releaseGroupRollupDrift', releaseGroupRollupDrift)
          ..add('sortKeyDrift', sortKeyDrift)
          ..add('bookDurationDrift', bookDurationDrift)
          ..add('bookIsbnKeyDrift', bookIsbnKeyDrift)
          ..add('albumYearDrift', albumYearDrift)
          ..add('releaseYearDrift', releaseYearDrift)
          ..add('playlistPositionDrift', playlistPositionDrift)
          ..add('orphanArtSources', orphanArtSources)
          ..add('orphanThumbnails', orphanThumbnails)
          ..add('orphanTagProvenance', orphanTagProvenance)
          ..add('strandedTagRows', strandedTagRows)
          ..add('consistent', consistent)
          ..add('reclaimable', reclaimable))
        .toString();
  }
}

class CatalogConsistencyBuilder
    implements Builder<CatalogConsistency, CatalogConsistencyBuilder> {
  _$CatalogConsistency? _$v;

  int? _itemsMissingFromSearch;
  int? get itemsMissingFromSearch => _$this._itemsMissingFromSearch;
  set itemsMissingFromSearch(int? itemsMissingFromSearch) =>
      _$this._itemsMissingFromSearch = itemsMissingFromSearch;

  int? _orphanSearchRows;
  int? get orphanSearchRows => _$this._orphanSearchRows;
  set orphanSearchRows(int? orphanSearchRows) =>
      _$this._orphanSearchRows = orphanSearchRows;

  int? _artistRollupDrift;
  int? get artistRollupDrift => _$this._artistRollupDrift;
  set artistRollupDrift(int? artistRollupDrift) =>
      _$this._artistRollupDrift = artistRollupDrift;

  int? _genreRollupDrift;
  int? get genreRollupDrift => _$this._genreRollupDrift;
  set genreRollupDrift(int? genreRollupDrift) =>
      _$this._genreRollupDrift = genreRollupDrift;

  int? _releaseGroupRollupDrift;
  int? get releaseGroupRollupDrift => _$this._releaseGroupRollupDrift;
  set releaseGroupRollupDrift(int? releaseGroupRollupDrift) =>
      _$this._releaseGroupRollupDrift = releaseGroupRollupDrift;

  int? _sortKeyDrift;
  int? get sortKeyDrift => _$this._sortKeyDrift;
  set sortKeyDrift(int? sortKeyDrift) => _$this._sortKeyDrift = sortKeyDrift;

  int? _bookDurationDrift;
  int? get bookDurationDrift => _$this._bookDurationDrift;
  set bookDurationDrift(int? bookDurationDrift) =>
      _$this._bookDurationDrift = bookDurationDrift;

  int? _bookIsbnKeyDrift;
  int? get bookIsbnKeyDrift => _$this._bookIsbnKeyDrift;
  set bookIsbnKeyDrift(int? bookIsbnKeyDrift) =>
      _$this._bookIsbnKeyDrift = bookIsbnKeyDrift;

  int? _albumYearDrift;
  int? get albumYearDrift => _$this._albumYearDrift;
  set albumYearDrift(int? albumYearDrift) =>
      _$this._albumYearDrift = albumYearDrift;

  int? _releaseYearDrift;
  int? get releaseYearDrift => _$this._releaseYearDrift;
  set releaseYearDrift(int? releaseYearDrift) =>
      _$this._releaseYearDrift = releaseYearDrift;

  int? _playlistPositionDrift;
  int? get playlistPositionDrift => _$this._playlistPositionDrift;
  set playlistPositionDrift(int? playlistPositionDrift) =>
      _$this._playlistPositionDrift = playlistPositionDrift;

  int? _orphanArtSources;
  int? get orphanArtSources => _$this._orphanArtSources;
  set orphanArtSources(int? orphanArtSources) =>
      _$this._orphanArtSources = orphanArtSources;

  int? _orphanThumbnails;
  int? get orphanThumbnails => _$this._orphanThumbnails;
  set orphanThumbnails(int? orphanThumbnails) =>
      _$this._orphanThumbnails = orphanThumbnails;

  int? _orphanTagProvenance;
  int? get orphanTagProvenance => _$this._orphanTagProvenance;
  set orphanTagProvenance(int? orphanTagProvenance) =>
      _$this._orphanTagProvenance = orphanTagProvenance;

  int? _strandedTagRows;
  int? get strandedTagRows => _$this._strandedTagRows;
  set strandedTagRows(int? strandedTagRows) =>
      _$this._strandedTagRows = strandedTagRows;

  bool? _consistent;
  bool? get consistent => _$this._consistent;
  set consistent(bool? consistent) => _$this._consistent = consistent;

  bool? _reclaimable;
  bool? get reclaimable => _$this._reclaimable;
  set reclaimable(bool? reclaimable) => _$this._reclaimable = reclaimable;

  CatalogConsistencyBuilder() {
    CatalogConsistency._defaults(this);
  }

  CatalogConsistencyBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _itemsMissingFromSearch = $v.itemsMissingFromSearch;
      _orphanSearchRows = $v.orphanSearchRows;
      _artistRollupDrift = $v.artistRollupDrift;
      _genreRollupDrift = $v.genreRollupDrift;
      _releaseGroupRollupDrift = $v.releaseGroupRollupDrift;
      _sortKeyDrift = $v.sortKeyDrift;
      _bookDurationDrift = $v.bookDurationDrift;
      _bookIsbnKeyDrift = $v.bookIsbnKeyDrift;
      _albumYearDrift = $v.albumYearDrift;
      _releaseYearDrift = $v.releaseYearDrift;
      _playlistPositionDrift = $v.playlistPositionDrift;
      _orphanArtSources = $v.orphanArtSources;
      _orphanThumbnails = $v.orphanThumbnails;
      _orphanTagProvenance = $v.orphanTagProvenance;
      _strandedTagRows = $v.strandedTagRows;
      _consistent = $v.consistent;
      _reclaimable = $v.reclaimable;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CatalogConsistency other) {
    _$v = other as _$CatalogConsistency;
  }

  @override
  void update(void Function(CatalogConsistencyBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CatalogConsistency build() => _build();

  _$CatalogConsistency _build() {
    final _$result =
        _$v ??
        _$CatalogConsistency._(
          itemsMissingFromSearch: BuiltValueNullFieldError.checkNotNull(
            itemsMissingFromSearch,
            r'CatalogConsistency',
            'itemsMissingFromSearch',
          ),
          orphanSearchRows: BuiltValueNullFieldError.checkNotNull(
            orphanSearchRows,
            r'CatalogConsistency',
            'orphanSearchRows',
          ),
          artistRollupDrift: BuiltValueNullFieldError.checkNotNull(
            artistRollupDrift,
            r'CatalogConsistency',
            'artistRollupDrift',
          ),
          genreRollupDrift: BuiltValueNullFieldError.checkNotNull(
            genreRollupDrift,
            r'CatalogConsistency',
            'genreRollupDrift',
          ),
          releaseGroupRollupDrift: BuiltValueNullFieldError.checkNotNull(
            releaseGroupRollupDrift,
            r'CatalogConsistency',
            'releaseGroupRollupDrift',
          ),
          sortKeyDrift: BuiltValueNullFieldError.checkNotNull(
            sortKeyDrift,
            r'CatalogConsistency',
            'sortKeyDrift',
          ),
          bookDurationDrift: BuiltValueNullFieldError.checkNotNull(
            bookDurationDrift,
            r'CatalogConsistency',
            'bookDurationDrift',
          ),
          bookIsbnKeyDrift: BuiltValueNullFieldError.checkNotNull(
            bookIsbnKeyDrift,
            r'CatalogConsistency',
            'bookIsbnKeyDrift',
          ),
          albumYearDrift: BuiltValueNullFieldError.checkNotNull(
            albumYearDrift,
            r'CatalogConsistency',
            'albumYearDrift',
          ),
          releaseYearDrift: BuiltValueNullFieldError.checkNotNull(
            releaseYearDrift,
            r'CatalogConsistency',
            'releaseYearDrift',
          ),
          playlistPositionDrift: BuiltValueNullFieldError.checkNotNull(
            playlistPositionDrift,
            r'CatalogConsistency',
            'playlistPositionDrift',
          ),
          orphanArtSources: BuiltValueNullFieldError.checkNotNull(
            orphanArtSources,
            r'CatalogConsistency',
            'orphanArtSources',
          ),
          orphanThumbnails: BuiltValueNullFieldError.checkNotNull(
            orphanThumbnails,
            r'CatalogConsistency',
            'orphanThumbnails',
          ),
          orphanTagProvenance: BuiltValueNullFieldError.checkNotNull(
            orphanTagProvenance,
            r'CatalogConsistency',
            'orphanTagProvenance',
          ),
          strandedTagRows: BuiltValueNullFieldError.checkNotNull(
            strandedTagRows,
            r'CatalogConsistency',
            'strandedTagRows',
          ),
          consistent: BuiltValueNullFieldError.checkNotNull(
            consistent,
            r'CatalogConsistency',
            'consistent',
          ),
          reclaimable: BuiltValueNullFieldError.checkNotNull(
            reclaimable,
            r'CatalogConsistency',
            'reclaimable',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
