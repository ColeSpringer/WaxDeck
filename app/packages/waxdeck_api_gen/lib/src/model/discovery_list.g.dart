// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discovery_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DiscoveryList _$newest = const DiscoveryList._('newest');
const DiscoveryList _$recentlyAdded = const DiscoveryList._('recentlyAdded');
const DiscoveryList _$mostPlayed = const DiscoveryList._('mostPlayed');
const DiscoveryList _$recentlyPlayed = const DiscoveryList._('recentlyPlayed');
const DiscoveryList _$random = const DiscoveryList._('random');
const DiscoveryList _$starred = const DiscoveryList._('starred');
const DiscoveryList _$alphabetical = const DiscoveryList._('alphabetical');
const DiscoveryList _$neverPlayed = const DiscoveryList._('neverPlayed');
const DiscoveryList _$rediscover = const DiscoveryList._('rediscover');

DiscoveryList _$valueOf(String name) {
  switch (name) {
    case 'newest':
      return _$newest;
    case 'recentlyAdded':
      return _$recentlyAdded;
    case 'mostPlayed':
      return _$mostPlayed;
    case 'recentlyPlayed':
      return _$recentlyPlayed;
    case 'random':
      return _$random;
    case 'starred':
      return _$starred;
    case 'alphabetical':
      return _$alphabetical;
    case 'neverPlayed':
      return _$neverPlayed;
    case 'rediscover':
      return _$rediscover;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DiscoveryList> _$values =
    BuiltSet<DiscoveryList>(const <DiscoveryList>[
      _$newest,
      _$recentlyAdded,
      _$mostPlayed,
      _$recentlyPlayed,
      _$random,
      _$starred,
      _$alphabetical,
      _$neverPlayed,
      _$rediscover,
    ]);

class _$DiscoveryListMeta {
  const _$DiscoveryListMeta();
  DiscoveryList get newest => _$newest;
  DiscoveryList get recentlyAdded => _$recentlyAdded;
  DiscoveryList get mostPlayed => _$mostPlayed;
  DiscoveryList get recentlyPlayed => _$recentlyPlayed;
  DiscoveryList get random => _$random;
  DiscoveryList get starred => _$starred;
  DiscoveryList get alphabetical => _$alphabetical;
  DiscoveryList get neverPlayed => _$neverPlayed;
  DiscoveryList get rediscover => _$rediscover;
  DiscoveryList valueOf(String name) => _$valueOf(name);
  BuiltSet<DiscoveryList> get values => _$values;
}

mixin _$DiscoveryListMixin {
  // ignore: non_constant_identifier_names
  _$DiscoveryListMeta get DiscoveryList => const _$DiscoveryListMeta();
}

Serializer<DiscoveryList> _$discoveryListSerializer =
    _$DiscoveryListSerializer();

class _$DiscoveryListSerializer implements PrimitiveSerializer<DiscoveryList> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'newest': 'newest',
    'recentlyAdded': 'recently-added',
    'mostPlayed': 'most-played',
    'recentlyPlayed': 'recently-played',
    'random': 'random',
    'starred': 'starred',
    'alphabetical': 'alphabetical',
    'neverPlayed': 'never-played',
    'rediscover': 'rediscover',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'newest': 'newest',
    'recently-added': 'recentlyAdded',
    'most-played': 'mostPlayed',
    'recently-played': 'recentlyPlayed',
    'random': 'random',
    'starred': 'starred',
    'alphabetical': 'alphabetical',
    'never-played': 'neverPlayed',
    'rediscover': 'rediscover',
  };

  @override
  final Iterable<Type> types = const <Type>[DiscoveryList];
  @override
  final String wireName = 'DiscoveryList';

  @override
  Object serialize(
    Serializers serializers,
    DiscoveryList object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  DiscoveryList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => DiscoveryList.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
