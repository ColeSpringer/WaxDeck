//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'acquisition_format.g.dart';

class AcquisitionFormat extends EnumClass {

  /// Preferred delivered audio format for a URL acquisition. \"best\", the default, copies the source's highest-quality audio with no re-encode (Opus, in practice, for YouTube). The others transcode to that container for device compatibility, at some quality cost from a lossy source (FLAC is a lossless container of that same lossy audio, not a quality gain). 
  @BuiltValueEnumConst(wireName: r'best')
  static const AcquisitionFormat best = _$best;
  /// Preferred delivered audio format for a URL acquisition. \"best\", the default, copies the source's highest-quality audio with no re-encode (Opus, in practice, for YouTube). The others transcode to that container for device compatibility, at some quality cost from a lossy source (FLAC is a lossless container of that same lossy audio, not a quality gain). 
  @BuiltValueEnumConst(wireName: r'opus')
  static const AcquisitionFormat opus = _$opus;
  /// Preferred delivered audio format for a URL acquisition. \"best\", the default, copies the source's highest-quality audio with no re-encode (Opus, in practice, for YouTube). The others transcode to that container for device compatibility, at some quality cost from a lossy source (FLAC is a lossless container of that same lossy audio, not a quality gain). 
  @BuiltValueEnumConst(wireName: r'mp3')
  static const AcquisitionFormat mp3 = _$mp3;
  /// Preferred delivered audio format for a URL acquisition. \"best\", the default, copies the source's highest-quality audio with no re-encode (Opus, in practice, for YouTube). The others transcode to that container for device compatibility, at some quality cost from a lossy source (FLAC is a lossless container of that same lossy audio, not a quality gain). 
  @BuiltValueEnumConst(wireName: r'm4a')
  static const AcquisitionFormat m4a = _$m4a;
  /// Preferred delivered audio format for a URL acquisition. \"best\", the default, copies the source's highest-quality audio with no re-encode (Opus, in practice, for YouTube). The others transcode to that container for device compatibility, at some quality cost from a lossy source (FLAC is a lossless container of that same lossy audio, not a quality gain). 
  @BuiltValueEnumConst(wireName: r'flac')
  static const AcquisitionFormat flac = _$flac;
  /// Preferred delivered audio format for a URL acquisition. \"best\", the default, copies the source's highest-quality audio with no re-encode (Opus, in practice, for YouTube). The others transcode to that container for device compatibility, at some quality cost from a lossy source (FLAC is a lossless container of that same lossy audio, not a quality gain). 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const AcquisitionFormat unknownDefaultOpenApi = _$unknownDefaultOpenApi;

  static Serializer<AcquisitionFormat> get serializer => _$acquisitionFormatSerializer;

  const AcquisitionFormat._(String name): super(name);

  static BuiltSet<AcquisitionFormat> get values => _$values;
  static AcquisitionFormat valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class AcquisitionFormatMixin = Object with _$AcquisitionFormatMixin;

