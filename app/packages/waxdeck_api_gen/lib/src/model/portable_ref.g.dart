// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'portable_ref.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PortableRefKindEnum _$portableRefKindEnum_track =
    const PortableRefKindEnum._('track');
const PortableRefKindEnum _$portableRefKindEnum_book =
    const PortableRefKindEnum._('book');
const PortableRefKindEnum _$portableRefKindEnum_episode =
    const PortableRefKindEnum._('episode');
const PortableRefKindEnum _$portableRefKindEnum_unknownDefaultOpenApi =
    const PortableRefKindEnum._('unknownDefaultOpenApi');

PortableRefKindEnum _$portableRefKindEnumValueOf(String name) {
  switch (name) {
    case 'track':
      return _$portableRefKindEnum_track;
    case 'book':
      return _$portableRefKindEnum_book;
    case 'episode':
      return _$portableRefKindEnum_episode;
    case 'unknownDefaultOpenApi':
      return _$portableRefKindEnum_unknownDefaultOpenApi;
    default:
      return _$portableRefKindEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<PortableRefKindEnum> _$portableRefKindEnumValues =
    BuiltSet<PortableRefKindEnum>(const <PortableRefKindEnum>[
      _$portableRefKindEnum_track,
      _$portableRefKindEnum_book,
      _$portableRefKindEnum_episode,
      _$portableRefKindEnum_unknownDefaultOpenApi,
    ]);

Serializer<PortableRefKindEnum> _$portableRefKindEnumSerializer =
    _$PortableRefKindEnumSerializer();

class _$PortableRefKindEnumSerializer
    implements PrimitiveSerializer<PortableRefKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'track': 'track',
    'book': 'book',
    'episode': 'episode',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'track': 'track',
    'book': 'book',
    'episode': 'episode',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[PortableRefKindEnum];
  @override
  final String wireName = 'PortableRefKindEnum';

  @override
  Object serialize(
    Serializers serializers,
    PortableRefKindEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  PortableRefKindEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => PortableRefKindEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$PortableRef extends PortableRef {
  @override
  final PortableRefKindEnum kind;
  @override
  final String? essence;
  @override
  final String? fingerprint;
  @override
  final int? fingerprintAlgo;
  @override
  final String? mbid;
  @override
  final String? asin;
  @override
  final String? isbn;
  @override
  final String? isrc;
  @override
  final String? artist;
  @override
  final String title;
  @override
  final String? album;
  @override
  final int? durationMs;

  factory _$PortableRef([void Function(PortableRefBuilder)? updates]) =>
      (PortableRefBuilder()..update(updates))._build();

  _$PortableRef._({
    required this.kind,
    this.essence,
    this.fingerprint,
    this.fingerprintAlgo,
    this.mbid,
    this.asin,
    this.isbn,
    this.isrc,
    this.artist,
    required this.title,
    this.album,
    this.durationMs,
  }) : super._();
  @override
  PortableRef rebuild(void Function(PortableRefBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PortableRefBuilder toBuilder() => PortableRefBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PortableRef &&
        kind == other.kind &&
        essence == other.essence &&
        fingerprint == other.fingerprint &&
        fingerprintAlgo == other.fingerprintAlgo &&
        mbid == other.mbid &&
        asin == other.asin &&
        isbn == other.isbn &&
        isrc == other.isrc &&
        artist == other.artist &&
        title == other.title &&
        album == other.album &&
        durationMs == other.durationMs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, essence.hashCode);
    _$hash = $jc(_$hash, fingerprint.hashCode);
    _$hash = $jc(_$hash, fingerprintAlgo.hashCode);
    _$hash = $jc(_$hash, mbid.hashCode);
    _$hash = $jc(_$hash, asin.hashCode);
    _$hash = $jc(_$hash, isbn.hashCode);
    _$hash = $jc(_$hash, isrc.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, album.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PortableRef')
          ..add('kind', kind)
          ..add('essence', essence)
          ..add('fingerprint', fingerprint)
          ..add('fingerprintAlgo', fingerprintAlgo)
          ..add('mbid', mbid)
          ..add('asin', asin)
          ..add('isbn', isbn)
          ..add('isrc', isrc)
          ..add('artist', artist)
          ..add('title', title)
          ..add('album', album)
          ..add('durationMs', durationMs))
        .toString();
  }
}

class PortableRefBuilder implements Builder<PortableRef, PortableRefBuilder> {
  _$PortableRef? _$v;

  PortableRefKindEnum? _kind;
  PortableRefKindEnum? get kind => _$this._kind;
  set kind(PortableRefKindEnum? kind) => _$this._kind = kind;

  String? _essence;
  String? get essence => _$this._essence;
  set essence(String? essence) => _$this._essence = essence;

  String? _fingerprint;
  String? get fingerprint => _$this._fingerprint;
  set fingerprint(String? fingerprint) => _$this._fingerprint = fingerprint;

  int? _fingerprintAlgo;
  int? get fingerprintAlgo => _$this._fingerprintAlgo;
  set fingerprintAlgo(int? fingerprintAlgo) =>
      _$this._fingerprintAlgo = fingerprintAlgo;

  String? _mbid;
  String? get mbid => _$this._mbid;
  set mbid(String? mbid) => _$this._mbid = mbid;

  String? _asin;
  String? get asin => _$this._asin;
  set asin(String? asin) => _$this._asin = asin;

  String? _isbn;
  String? get isbn => _$this._isbn;
  set isbn(String? isbn) => _$this._isbn = isbn;

  String? _isrc;
  String? get isrc => _$this._isrc;
  set isrc(String? isrc) => _$this._isrc = isrc;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _album;
  String? get album => _$this._album;
  set album(String? album) => _$this._album = album;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  PortableRefBuilder() {
    PortableRef._defaults(this);
  }

  PortableRefBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _essence = $v.essence;
      _fingerprint = $v.fingerprint;
      _fingerprintAlgo = $v.fingerprintAlgo;
      _mbid = $v.mbid;
      _asin = $v.asin;
      _isbn = $v.isbn;
      _isrc = $v.isrc;
      _artist = $v.artist;
      _title = $v.title;
      _album = $v.album;
      _durationMs = $v.durationMs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PortableRef other) {
    _$v = other as _$PortableRef;
  }

  @override
  void update(void Function(PortableRefBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PortableRef build() => _build();

  _$PortableRef _build() {
    final _$result =
        _$v ??
        _$PortableRef._(
          kind: BuiltValueNullFieldError.checkNotNull(
            kind,
            r'PortableRef',
            'kind',
          ),
          essence: essence,
          fingerprint: fingerprint,
          fingerprintAlgo: fingerprintAlgo,
          mbid: mbid,
          asin: asin,
          isbn: isbn,
          isrc: isrc,
          artist: artist,
          title: BuiltValueNullFieldError.checkNotNull(
            title,
            r'PortableRef',
            'title',
          ),
          album: album,
          durationMs: durationMs,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
