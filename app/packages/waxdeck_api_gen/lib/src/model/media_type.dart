//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'media_type.g.dart';

class MediaType extends EnumClass {

  /// The three first-class media types.
  @BuiltValueEnumConst(wireName: r'music')
  static const MediaType music = _$music;
  /// The three first-class media types.
  @BuiltValueEnumConst(wireName: r'podcast')
  static const MediaType podcast = _$podcast;
  /// The three first-class media types.
  @BuiltValueEnumConst(wireName: r'audiobook')
  static const MediaType audiobook = _$audiobook;

  static Serializer<MediaType> get serializer => _$mediaTypeSerializer;

  const MediaType._(String name): super(name);

  static BuiltSet<MediaType> get values => _$values;
  static MediaType valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class MediaTypeMixin = Object with _$MediaTypeMixin;

