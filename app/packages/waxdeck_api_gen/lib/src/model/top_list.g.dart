// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'top_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const TopListKindEnum _$topListKindEnum_artists = const TopListKindEnum._(
  'artists',
);
const TopListKindEnum _$topListKindEnum_albums = const TopListKindEnum._(
  'albums',
);
const TopListKindEnum _$topListKindEnum_genres = const TopListKindEnum._(
  'genres',
);
const TopListKindEnum _$topListKindEnum_shows = const TopListKindEnum._(
  'shows',
);
const TopListKindEnum _$topListKindEnum_stations = const TopListKindEnum._(
  'stations',
);
const TopListKindEnum _$topListKindEnum_unknownDefaultOpenApi =
    const TopListKindEnum._('unknownDefaultOpenApi');

TopListKindEnum _$topListKindEnumValueOf(String name) {
  switch (name) {
    case 'artists':
      return _$topListKindEnum_artists;
    case 'albums':
      return _$topListKindEnum_albums;
    case 'genres':
      return _$topListKindEnum_genres;
    case 'shows':
      return _$topListKindEnum_shows;
    case 'stations':
      return _$topListKindEnum_stations;
    case 'unknownDefaultOpenApi':
      return _$topListKindEnum_unknownDefaultOpenApi;
    default:
      return _$topListKindEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<TopListKindEnum> _$topListKindEnumValues =
    BuiltSet<TopListKindEnum>(const <TopListKindEnum>[
      _$topListKindEnum_artists,
      _$topListKindEnum_albums,
      _$topListKindEnum_genres,
      _$topListKindEnum_shows,
      _$topListKindEnum_stations,
      _$topListKindEnum_unknownDefaultOpenApi,
    ]);

const TopListRangeEnum _$topListRangeEnum_n7d = const TopListRangeEnum._('n7d');
const TopListRangeEnum _$topListRangeEnum_n30d = const TopListRangeEnum._(
  'n30d',
);
const TopListRangeEnum _$topListRangeEnum_n90d = const TopListRangeEnum._(
  'n90d',
);
const TopListRangeEnum _$topListRangeEnum_n365d = const TopListRangeEnum._(
  'n365d',
);
const TopListRangeEnum _$topListRangeEnum_all = const TopListRangeEnum._('all');
const TopListRangeEnum _$topListRangeEnum_unknownDefaultOpenApi =
    const TopListRangeEnum._('unknownDefaultOpenApi');

TopListRangeEnum _$topListRangeEnumValueOf(String name) {
  switch (name) {
    case 'n7d':
      return _$topListRangeEnum_n7d;
    case 'n30d':
      return _$topListRangeEnum_n30d;
    case 'n90d':
      return _$topListRangeEnum_n90d;
    case 'n365d':
      return _$topListRangeEnum_n365d;
    case 'all':
      return _$topListRangeEnum_all;
    case 'unknownDefaultOpenApi':
      return _$topListRangeEnum_unknownDefaultOpenApi;
    default:
      return _$topListRangeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<TopListRangeEnum> _$topListRangeEnumValues =
    BuiltSet<TopListRangeEnum>(const <TopListRangeEnum>[
      _$topListRangeEnum_n7d,
      _$topListRangeEnum_n30d,
      _$topListRangeEnum_n90d,
      _$topListRangeEnum_n365d,
      _$topListRangeEnum_all,
      _$topListRangeEnum_unknownDefaultOpenApi,
    ]);

Serializer<TopListKindEnum> _$topListKindEnumSerializer =
    _$TopListKindEnumSerializer();
Serializer<TopListRangeEnum> _$topListRangeEnumSerializer =
    _$TopListRangeEnumSerializer();

class _$TopListKindEnumSerializer
    implements PrimitiveSerializer<TopListKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'artists': 'artists',
    'albums': 'albums',
    'genres': 'genres',
    'shows': 'shows',
    'stations': 'stations',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'artists': 'artists',
    'albums': 'albums',
    'genres': 'genres',
    'shows': 'shows',
    'stations': 'stations',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[TopListKindEnum];
  @override
  final String wireName = 'TopListKindEnum';

  @override
  Object serialize(
    Serializers serializers,
    TopListKindEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  TopListKindEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => TopListKindEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$TopListRangeEnumSerializer
    implements PrimitiveSerializer<TopListRangeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'n7d': '7d',
    'n30d': '30d',
    'n90d': '90d',
    'n365d': '365d',
    'all': 'all',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    '7d': 'n7d',
    '30d': 'n30d',
    '90d': 'n90d',
    '365d': 'n365d',
    'all': 'all',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[TopListRangeEnum];
  @override
  final String wireName = 'TopListRangeEnum';

  @override
  Object serialize(
    Serializers serializers,
    TopListRangeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  TopListRangeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => TopListRangeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$TopList extends TopList {
  @override
  final TopListKindEnum kind;
  @override
  final TopListRangeEnum range;
  @override
  final BuiltList<TopEntry> entries;

  factory _$TopList([void Function(TopListBuilder)? updates]) =>
      (TopListBuilder()..update(updates))._build();

  _$TopList._({required this.kind, required this.range, required this.entries})
    : super._();
  @override
  TopList rebuild(void Function(TopListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TopListBuilder toBuilder() => TopListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TopList &&
        kind == other.kind &&
        range == other.range &&
        entries == other.entries;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, range.hashCode);
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TopList')
          ..add('kind', kind)
          ..add('range', range)
          ..add('entries', entries))
        .toString();
  }
}

class TopListBuilder implements Builder<TopList, TopListBuilder> {
  _$TopList? _$v;

  TopListKindEnum? _kind;
  TopListKindEnum? get kind => _$this._kind;
  set kind(TopListKindEnum? kind) => _$this._kind = kind;

  TopListRangeEnum? _range;
  TopListRangeEnum? get range => _$this._range;
  set range(TopListRangeEnum? range) => _$this._range = range;

  ListBuilder<TopEntry>? _entries;
  ListBuilder<TopEntry> get entries =>
      _$this._entries ??= ListBuilder<TopEntry>();
  set entries(ListBuilder<TopEntry>? entries) => _$this._entries = entries;

  TopListBuilder() {
    TopList._defaults(this);
  }

  TopListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _range = $v.range;
      _entries = $v.entries.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TopList other) {
    _$v = other as _$TopList;
  }

  @override
  void update(void Function(TopListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TopList build() => _build();

  _$TopList _build() {
    _$TopList _$result;
    try {
      _$result =
          _$v ??
          _$TopList._(
            kind: BuiltValueNullFieldError.checkNotNull(
              kind,
              r'TopList',
              'kind',
            ),
            range: BuiltValueNullFieldError.checkNotNull(
              range,
              r'TopList',
              'range',
            ),
            entries: entries.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'TopList',
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
