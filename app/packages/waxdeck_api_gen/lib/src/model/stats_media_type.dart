//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'stats_media_type.g.dart';

class StatsMediaType extends EnumClass {

  /// What a recorded listen was. The three first-class item kinds plus `radio`, which is measured in the stream proxy rather than reported by a client and belongs to no item. Deliberately not the shared `MediaType`: that enum is the item kinds browse, items, and uploads answer with, and none of them will ever answer `radio`. Named to stay clear of `MediaTypeListening`, the per-media total object one word-order away. 
  @BuiltValueEnumConst(wireName: r'music')
  static const StatsMediaType music = _$music;
  /// What a recorded listen was. The three first-class item kinds plus `radio`, which is measured in the stream proxy rather than reported by a client and belongs to no item. Deliberately not the shared `MediaType`: that enum is the item kinds browse, items, and uploads answer with, and none of them will ever answer `radio`. Named to stay clear of `MediaTypeListening`, the per-media total object one word-order away. 
  @BuiltValueEnumConst(wireName: r'podcast')
  static const StatsMediaType podcast = _$podcast;
  /// What a recorded listen was. The three first-class item kinds plus `radio`, which is measured in the stream proxy rather than reported by a client and belongs to no item. Deliberately not the shared `MediaType`: that enum is the item kinds browse, items, and uploads answer with, and none of them will ever answer `radio`. Named to stay clear of `MediaTypeListening`, the per-media total object one word-order away. 
  @BuiltValueEnumConst(wireName: r'audiobook')
  static const StatsMediaType audiobook = _$audiobook;
  /// What a recorded listen was. The three first-class item kinds plus `radio`, which is measured in the stream proxy rather than reported by a client and belongs to no item. Deliberately not the shared `MediaType`: that enum is the item kinds browse, items, and uploads answer with, and none of them will ever answer `radio`. Named to stay clear of `MediaTypeListening`, the per-media total object one word-order away. 
  @BuiltValueEnumConst(wireName: r'radio')
  static const StatsMediaType radio = _$radio;
  /// What a recorded listen was. The three first-class item kinds plus `radio`, which is measured in the stream proxy rather than reported by a client and belongs to no item. Deliberately not the shared `MediaType`: that enum is the item kinds browse, items, and uploads answer with, and none of them will ever answer `radio`. Named to stay clear of `MediaTypeListening`, the per-media total object one word-order away. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const StatsMediaType unknownDefaultOpenApi = _$unknownDefaultOpenApi;

  static Serializer<StatsMediaType> get serializer => _$statsMediaTypeSerializer;

  const StatsMediaType._(String name): super(name);

  static BuiltSet<StatsMediaType> get values => _$values;
  static StatsMediaType valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class StatsMediaTypeMixin = Object with _$StatsMediaTypeMixin;

