//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_grouping.g.dart';

class UploadGrouping extends EnumClass {

  /// How a batch's staged files reach the review queue: `album` opens one multi-file entry over all of them, `tracks` one entry per file, and `auto` clusters them into album units by their tags and relative paths (disc subfolders fold into their parent). 
  @BuiltValueEnumConst(wireName: r'auto')
  static const UploadGrouping auto = _$auto;
  /// How a batch's staged files reach the review queue: `album` opens one multi-file entry over all of them, `tracks` one entry per file, and `auto` clusters them into album units by their tags and relative paths (disc subfolders fold into their parent). 
  @BuiltValueEnumConst(wireName: r'album')
  static const UploadGrouping album = _$album;
  /// How a batch's staged files reach the review queue: `album` opens one multi-file entry over all of them, `tracks` one entry per file, and `auto` clusters them into album units by their tags and relative paths (disc subfolders fold into their parent). 
  @BuiltValueEnumConst(wireName: r'tracks')
  static const UploadGrouping tracks = _$tracks;
  /// How a batch's staged files reach the review queue: `album` opens one multi-file entry over all of them, `tracks` one entry per file, and `auto` clusters them into album units by their tags and relative paths (disc subfolders fold into their parent). 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const UploadGrouping unknownDefaultOpenApi = _$unknownDefaultOpenApi;

  static Serializer<UploadGrouping> get serializer => _$uploadGroupingSerializer;

  const UploadGrouping._(String name): super(name);

  static BuiltSet<UploadGrouping> get values => _$values;
  static UploadGrouping valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class UploadGroupingMixin = Object with _$UploadGroupingMixin;

