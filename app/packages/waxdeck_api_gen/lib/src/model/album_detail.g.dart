// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'album_detail.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AlbumDetail extends AlbumDetail {
  @override
  final String pid;
  @override
  final String title;
  @override
  final String? sortKey;
  @override
  final String? mbid;
  @override
  final int? year;
  @override
  final String? releaseGroupPid;
  @override
  final String? barcode;
  @override
  final String? label;
  @override
  final String? catalogNumber;
  @override
  final String? media;
  @override
  final String? country;
  @override
  final int? itemCount;
  @override
  final int? totalDurationMs;
  @override
  final ArtSource? artSource;

  factory _$AlbumDetail([void Function(AlbumDetailBuilder)? updates]) =>
      (AlbumDetailBuilder()..update(updates))._build();

  _$AlbumDetail._({
    required this.pid,
    required this.title,
    this.sortKey,
    this.mbid,
    this.year,
    this.releaseGroupPid,
    this.barcode,
    this.label,
    this.catalogNumber,
    this.media,
    this.country,
    this.itemCount,
    this.totalDurationMs,
    this.artSource,
  }) : super._();
  @override
  AlbumDetail rebuild(void Function(AlbumDetailBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AlbumDetailBuilder toBuilder() => AlbumDetailBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AlbumDetail &&
        pid == other.pid &&
        title == other.title &&
        sortKey == other.sortKey &&
        mbid == other.mbid &&
        year == other.year &&
        releaseGroupPid == other.releaseGroupPid &&
        barcode == other.barcode &&
        label == other.label &&
        catalogNumber == other.catalogNumber &&
        media == other.media &&
        country == other.country &&
        itemCount == other.itemCount &&
        totalDurationMs == other.totalDurationMs &&
        artSource == other.artSource;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, sortKey.hashCode);
    _$hash = $jc(_$hash, mbid.hashCode);
    _$hash = $jc(_$hash, year.hashCode);
    _$hash = $jc(_$hash, releaseGroupPid.hashCode);
    _$hash = $jc(_$hash, barcode.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, catalogNumber.hashCode);
    _$hash = $jc(_$hash, media.hashCode);
    _$hash = $jc(_$hash, country.hashCode);
    _$hash = $jc(_$hash, itemCount.hashCode);
    _$hash = $jc(_$hash, totalDurationMs.hashCode);
    _$hash = $jc(_$hash, artSource.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AlbumDetail')
          ..add('pid', pid)
          ..add('title', title)
          ..add('sortKey', sortKey)
          ..add('mbid', mbid)
          ..add('year', year)
          ..add('releaseGroupPid', releaseGroupPid)
          ..add('barcode', barcode)
          ..add('label', label)
          ..add('catalogNumber', catalogNumber)
          ..add('media', media)
          ..add('country', country)
          ..add('itemCount', itemCount)
          ..add('totalDurationMs', totalDurationMs)
          ..add('artSource', artSource))
        .toString();
  }
}

class AlbumDetailBuilder implements Builder<AlbumDetail, AlbumDetailBuilder> {
  _$AlbumDetail? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _sortKey;
  String? get sortKey => _$this._sortKey;
  set sortKey(String? sortKey) => _$this._sortKey = sortKey;

  String? _mbid;
  String? get mbid => _$this._mbid;
  set mbid(String? mbid) => _$this._mbid = mbid;

  int? _year;
  int? get year => _$this._year;
  set year(int? year) => _$this._year = year;

  String? _releaseGroupPid;
  String? get releaseGroupPid => _$this._releaseGroupPid;
  set releaseGroupPid(String? releaseGroupPid) =>
      _$this._releaseGroupPid = releaseGroupPid;

  String? _barcode;
  String? get barcode => _$this._barcode;
  set barcode(String? barcode) => _$this._barcode = barcode;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  String? _catalogNumber;
  String? get catalogNumber => _$this._catalogNumber;
  set catalogNumber(String? catalogNumber) =>
      _$this._catalogNumber = catalogNumber;

  String? _media;
  String? get media => _$this._media;
  set media(String? media) => _$this._media = media;

  String? _country;
  String? get country => _$this._country;
  set country(String? country) => _$this._country = country;

  int? _itemCount;
  int? get itemCount => _$this._itemCount;
  set itemCount(int? itemCount) => _$this._itemCount = itemCount;

  int? _totalDurationMs;
  int? get totalDurationMs => _$this._totalDurationMs;
  set totalDurationMs(int? totalDurationMs) =>
      _$this._totalDurationMs = totalDurationMs;

  ArtSourceBuilder? _artSource;
  ArtSourceBuilder get artSource => _$this._artSource ??= ArtSourceBuilder();
  set artSource(ArtSourceBuilder? artSource) => _$this._artSource = artSource;

  AlbumDetailBuilder() {
    AlbumDetail._defaults(this);
  }

  AlbumDetailBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _title = $v.title;
      _sortKey = $v.sortKey;
      _mbid = $v.mbid;
      _year = $v.year;
      _releaseGroupPid = $v.releaseGroupPid;
      _barcode = $v.barcode;
      _label = $v.label;
      _catalogNumber = $v.catalogNumber;
      _media = $v.media;
      _country = $v.country;
      _itemCount = $v.itemCount;
      _totalDurationMs = $v.totalDurationMs;
      _artSource = $v.artSource?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AlbumDetail other) {
    _$v = other as _$AlbumDetail;
  }

  @override
  void update(void Function(AlbumDetailBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AlbumDetail build() => _build();

  _$AlbumDetail _build() {
    _$AlbumDetail _$result;
    try {
      _$result =
          _$v ??
          _$AlbumDetail._(
            pid: BuiltValueNullFieldError.checkNotNull(
              pid,
              r'AlbumDetail',
              'pid',
            ),
            title: BuiltValueNullFieldError.checkNotNull(
              title,
              r'AlbumDetail',
              'title',
            ),
            sortKey: sortKey,
            mbid: mbid,
            year: year,
            releaseGroupPid: releaseGroupPid,
            barcode: barcode,
            label: label,
            catalogNumber: catalogNumber,
            media: media,
            country: country,
            itemCount: itemCount,
            totalDurationMs: totalDurationMs,
            artSource: _artSource?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'artSource';
        _artSource?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'AlbumDetail',
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
