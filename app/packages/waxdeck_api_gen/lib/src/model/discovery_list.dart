//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'discovery_list.g.dart';

/// Discovery lists for browsing. `most-played`, `recently-played`, `starred`, `never-played`, `rediscover`, and `in-progress` reflect the calling user's own listening state. `never-played` is what the caller has never counted a play of, and `rediscover` is what they starred or rated at least 80 and have not played in six months (never counts as six months, so something starred and never reached belongs there). \"Played\" on both is the same threshold `playCount` counts, so an item abandoned early enough to have never crossed it is still sealed. Both come back A to Z, since neither is ordered by anything a listener would recognize: there is no play stamp to sort a never-played item by, and sorting the other by how stale it is would put the most forgotten thing first every time the shelf is drawn. The others keep the orders their names describe. `in-progress` is what the caller is part way through: a saved position on something not finished, most recently progressed first. An episode or an audiobook is on it from its first saved position, whether or not a play has counted. A track is on it only once a play of it has counted, the membership `recently-played` has: a position is saved for a track skipped a few seconds in as for any other, and that is not something to carry on with. 
class DiscoveryList extends EnumClass {

  @BuiltValueEnumConst(wireName: r'newest')
  static const DiscoveryList newest = _$newest;
  @BuiltValueEnumConst(wireName: r'recently-added')
  static const DiscoveryList recentlyAdded = _$recentlyAdded;
  @BuiltValueEnumConst(wireName: r'most-played')
  static const DiscoveryList mostPlayed = _$mostPlayed;
  @BuiltValueEnumConst(wireName: r'recently-played')
  static const DiscoveryList recentlyPlayed = _$recentlyPlayed;
  @BuiltValueEnumConst(wireName: r'random')
  static const DiscoveryList random = _$random;
  @BuiltValueEnumConst(wireName: r'starred')
  static const DiscoveryList starred = _$starred;
  @BuiltValueEnumConst(wireName: r'alphabetical')
  static const DiscoveryList alphabetical = _$alphabetical;
  @BuiltValueEnumConst(wireName: r'never-played')
  static const DiscoveryList neverPlayed = _$neverPlayed;
  @BuiltValueEnumConst(wireName: r'rediscover')
  static const DiscoveryList rediscover = _$rediscover;
  @BuiltValueEnumConst(wireName: r'in-progress')
  static const DiscoveryList inProgress = _$inProgress;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const DiscoveryList unknownDefaultOpenApi = _$unknownDefaultOpenApi;

  static Serializer<DiscoveryList> get serializer => _$discoveryListSerializer;

  const DiscoveryList._(String name): super(name);

  static BuiltSet<DiscoveryList> get values => _$values;
  static DiscoveryList valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class DiscoveryListMixin = Object with _$DiscoveryListMixin;

