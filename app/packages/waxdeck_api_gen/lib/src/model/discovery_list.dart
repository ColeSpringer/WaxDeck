//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'discovery_list.g.dart';

class DiscoveryList extends EnumClass {

  /// Discovery lists for browsing. `most-played`, `recently-played`, and `starred` reflect the calling user's own listening state. 
  @BuiltValueEnumConst(wireName: r'newest')
  static const DiscoveryList newest = _$newest;
  /// Discovery lists for browsing. `most-played`, `recently-played`, and `starred` reflect the calling user's own listening state. 
  @BuiltValueEnumConst(wireName: r'recently-added')
  static const DiscoveryList recentlyAdded = _$recentlyAdded;
  /// Discovery lists for browsing. `most-played`, `recently-played`, and `starred` reflect the calling user's own listening state. 
  @BuiltValueEnumConst(wireName: r'most-played')
  static const DiscoveryList mostPlayed = _$mostPlayed;
  /// Discovery lists for browsing. `most-played`, `recently-played`, and `starred` reflect the calling user's own listening state. 
  @BuiltValueEnumConst(wireName: r'recently-played')
  static const DiscoveryList recentlyPlayed = _$recentlyPlayed;
  /// Discovery lists for browsing. `most-played`, `recently-played`, and `starred` reflect the calling user's own listening state. 
  @BuiltValueEnumConst(wireName: r'random')
  static const DiscoveryList random = _$random;
  /// Discovery lists for browsing. `most-played`, `recently-played`, and `starred` reflect the calling user's own listening state. 
  @BuiltValueEnumConst(wireName: r'starred')
  static const DiscoveryList starred = _$starred;
  /// Discovery lists for browsing. `most-played`, `recently-played`, and `starred` reflect the calling user's own listening state. 
  @BuiltValueEnumConst(wireName: r'alphabetical')
  static const DiscoveryList alphabetical = _$alphabetical;

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

