// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entity_card.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const EntityCardKindEnum _$entityCardKindEnum_album =
    const EntityCardKindEnum._('album');
const EntityCardKindEnum _$entityCardKindEnum_artist =
    const EntityCardKindEnum._('artist');
const EntityCardKindEnum _$entityCardKindEnum_releaseGroup =
    const EntityCardKindEnum._('releaseGroup');
const EntityCardKindEnum _$entityCardKindEnum_playlist =
    const EntityCardKindEnum._('playlist');
const EntityCardKindEnum _$entityCardKindEnum_podcast =
    const EntityCardKindEnum._('podcast');
const EntityCardKindEnum _$entityCardKindEnum_book = const EntityCardKindEnum._(
  'book',
);

EntityCardKindEnum _$entityCardKindEnumValueOf(String name) {
  switch (name) {
    case 'album':
      return _$entityCardKindEnum_album;
    case 'artist':
      return _$entityCardKindEnum_artist;
    case 'releaseGroup':
      return _$entityCardKindEnum_releaseGroup;
    case 'playlist':
      return _$entityCardKindEnum_playlist;
    case 'podcast':
      return _$entityCardKindEnum_podcast;
    case 'book':
      return _$entityCardKindEnum_book;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<EntityCardKindEnum> _$entityCardKindEnumValues =
    BuiltSet<EntityCardKindEnum>(const <EntityCardKindEnum>[
      _$entityCardKindEnum_album,
      _$entityCardKindEnum_artist,
      _$entityCardKindEnum_releaseGroup,
      _$entityCardKindEnum_playlist,
      _$entityCardKindEnum_podcast,
      _$entityCardKindEnum_book,
    ]);

Serializer<EntityCardKindEnum> _$entityCardKindEnumSerializer =
    _$EntityCardKindEnumSerializer();

class _$EntityCardKindEnumSerializer
    implements PrimitiveSerializer<EntityCardKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'album': 'album',
    'artist': 'artist',
    'releaseGroup': 'release-group',
    'playlist': 'playlist',
    'podcast': 'podcast',
    'book': 'book',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'album': 'album',
    'artist': 'artist',
    'release-group': 'releaseGroup',
    'playlist': 'playlist',
    'podcast': 'podcast',
    'book': 'book',
  };

  @override
  final Iterable<Type> types = const <Type>[EntityCardKindEnum];
  @override
  final String wireName = 'EntityCardKindEnum';

  @override
  Object serialize(
    Serializers serializers,
    EntityCardKindEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  EntityCardKindEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => EntityCardKindEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$EntityCard extends EntityCard {
  @override
  final String pid;
  @override
  final EntityCardKindEnum kind;
  @override
  final String title;
  @override
  final String? artist;
  @override
  final int? year;
  @override
  final int? itemCount;

  factory _$EntityCard([void Function(EntityCardBuilder)? updates]) =>
      (EntityCardBuilder()..update(updates))._build();

  _$EntityCard._({
    required this.pid,
    required this.kind,
    required this.title,
    this.artist,
    this.year,
    this.itemCount,
  }) : super._();
  @override
  EntityCard rebuild(void Function(EntityCardBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EntityCardBuilder toBuilder() => EntityCardBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EntityCard &&
        pid == other.pid &&
        kind == other.kind &&
        title == other.title &&
        artist == other.artist &&
        year == other.year &&
        itemCount == other.itemCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pid.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, artist.hashCode);
    _$hash = $jc(_$hash, year.hashCode);
    _$hash = $jc(_$hash, itemCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EntityCard')
          ..add('pid', pid)
          ..add('kind', kind)
          ..add('title', title)
          ..add('artist', artist)
          ..add('year', year)
          ..add('itemCount', itemCount))
        .toString();
  }
}

class EntityCardBuilder implements Builder<EntityCard, EntityCardBuilder> {
  _$EntityCard? _$v;

  String? _pid;
  String? get pid => _$this._pid;
  set pid(String? pid) => _$this._pid = pid;

  EntityCardKindEnum? _kind;
  EntityCardKindEnum? get kind => _$this._kind;
  set kind(EntityCardKindEnum? kind) => _$this._kind = kind;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _artist;
  String? get artist => _$this._artist;
  set artist(String? artist) => _$this._artist = artist;

  int? _year;
  int? get year => _$this._year;
  set year(int? year) => _$this._year = year;

  int? _itemCount;
  int? get itemCount => _$this._itemCount;
  set itemCount(int? itemCount) => _$this._itemCount = itemCount;

  EntityCardBuilder() {
    EntityCard._defaults(this);
  }

  EntityCardBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pid = $v.pid;
      _kind = $v.kind;
      _title = $v.title;
      _artist = $v.artist;
      _year = $v.year;
      _itemCount = $v.itemCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EntityCard other) {
    _$v = other as _$EntityCard;
  }

  @override
  void update(void Function(EntityCardBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EntityCard build() => _build();

  _$EntityCard _build() {
    final _$result =
        _$v ??
        _$EntityCard._(
          pid: BuiltValueNullFieldError.checkNotNull(pid, r'EntityCard', 'pid'),
          kind: BuiltValueNullFieldError.checkNotNull(
            kind,
            r'EntityCard',
            'kind',
          ),
          title: BuiltValueNullFieldError.checkNotNull(
            title,
            r'EntityCard',
            'title',
          ),
          artist: artist,
          year: year,
          itemCount: itemCount,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
