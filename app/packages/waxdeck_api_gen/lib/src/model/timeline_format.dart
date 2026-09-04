//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'timeline_format.g.dart';

class TimelineFormat extends EnumClass {

  /// An audio format a timeline can be rendered in. All four are carried in fragmented MP4; which of them a server can produce depends on its streaming engine build. 
  @BuiltValueEnumConst(wireName: r'aac')
  static const TimelineFormat aac = _$aac;
  /// An audio format a timeline can be rendered in. All four are carried in fragmented MP4; which of them a server can produce depends on its streaming engine build. 
  @BuiltValueEnumConst(wireName: r'flac')
  static const TimelineFormat flac = _$flac;
  /// An audio format a timeline can be rendered in. All four are carried in fragmented MP4; which of them a server can produce depends on its streaming engine build. 
  @BuiltValueEnumConst(wireName: r'opus')
  static const TimelineFormat opus = _$opus;
  /// An audio format a timeline can be rendered in. All four are carried in fragmented MP4; which of them a server can produce depends on its streaming engine build. 
  @BuiltValueEnumConst(wireName: r'alac')
  static const TimelineFormat alac = _$alac;
  /// An audio format a timeline can be rendered in. All four are carried in fragmented MP4; which of them a server can produce depends on its streaming engine build. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const TimelineFormat unknownDefaultOpenApi = _$unknownDefaultOpenApi;

  static Serializer<TimelineFormat> get serializer => _$timelineFormatSerializer;

  const TimelineFormat._(String name): super(name);

  static BuiltSet<TimelineFormat> get values => _$values;
  static TimelineFormat valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class TimelineFormatMixin = Object with _$TimelineFormatMixin;

