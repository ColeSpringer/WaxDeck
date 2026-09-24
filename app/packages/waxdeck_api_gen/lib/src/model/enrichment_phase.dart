//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_phase.g.dart';

class EnrichmentPhase extends EnumClass {

  /// One phase of the whole-library pass: `identity` is the MusicBrainz walks (artists, release groups, audiobooks), `releases` the release match, and the rest the backfills and fields walks they name. 
  @BuiltValueEnumConst(wireName: r'identity')
  static const EnrichmentPhase identity = _$identity;
  /// One phase of the whole-library pass: `identity` is the MusicBrainz walks (artists, release groups, audiobooks), `releases` the release match, and the rest the backfills and fields walks they name. 
  @BuiltValueEnumConst(wireName: r'releases')
  static const EnrichmentPhase releases = _$releases;
  /// One phase of the whole-library pass: `identity` is the MusicBrainz walks (artists, release groups, audiobooks), `releases` the release match, and the rest the backfills and fields walks they name. 
  @BuiltValueEnumConst(wireName: r'aux-art')
  static const EnrichmentPhase auxArt = _$auxArt;
  /// One phase of the whole-library pass: `identity` is the MusicBrainz walks (artists, release groups, audiobooks), `releases` the release match, and the rest the backfills and fields walks they name. 
  @BuiltValueEnumConst(wireName: r'artist-art')
  static const EnrichmentPhase artistArt = _$artistArt;
  /// One phase of the whole-library pass: `identity` is the MusicBrainz walks (artists, release groups, audiobooks), `releases` the release match, and the rest the backfills and fields walks they name. 
  @BuiltValueEnumConst(wireName: r'album-art')
  static const EnrichmentPhase albumArt = _$albumArt;
  /// One phase of the whole-library pass: `identity` is the MusicBrainz walks (artists, release groups, audiobooks), `releases` the release match, and the rest the backfills and fields walks they name. 
  @BuiltValueEnumConst(wireName: r'lyrics')
  static const EnrichmentPhase lyrics = _$lyrics;
  /// One phase of the whole-library pass: `identity` is the MusicBrainz walks (artists, release groups, audiobooks), `releases` the release match, and the rest the backfills and fields walks they name. 
  @BuiltValueEnumConst(wireName: r'track-fields')
  static const EnrichmentPhase trackFields = _$trackFields;
  /// One phase of the whole-library pass: `identity` is the MusicBrainz walks (artists, release groups, audiobooks), `releases` the release match, and the rest the backfills and fields walks they name. 
  @BuiltValueEnumConst(wireName: r'book-fields')
  static const EnrichmentPhase bookFields = _$bookFields;
  /// One phase of the whole-library pass: `identity` is the MusicBrainz walks (artists, release groups, audiobooks), `releases` the release match, and the rest the backfills and fields walks they name. 
  @BuiltValueEnumConst(wireName: r'album-fields')
  static const EnrichmentPhase albumFields = _$albumFields;
  /// One phase of the whole-library pass: `identity` is the MusicBrainz walks (artists, release groups, audiobooks), `releases` the release match, and the rest the backfills and fields walks they name. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const EnrichmentPhase unknownDefaultOpenApi = _$unknownDefaultOpenApi;

  static Serializer<EnrichmentPhase> get serializer => _$enrichmentPhaseSerializer;

  const EnrichmentPhase._(String name): super(name);

  static BuiltSet<EnrichmentPhase> get values => _$values;
  static EnrichmentPhase valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class EnrichmentPhaseMixin = Object with _$EnrichmentPhaseMixin;

