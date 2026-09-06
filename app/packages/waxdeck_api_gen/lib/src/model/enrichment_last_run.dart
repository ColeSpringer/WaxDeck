//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_last_run.g.dart';

/// What the most recent finished whole-library pass did. Absent until one has finished.  Coverage answers how much of the library is enriched; this answers whether the last pass accomplished anything, which coverage cannot. A pass that searched two thousand albums and matched none leaves coverage exactly where it was, and so does one whose every tag write failed; both read as \"nothing happened\" without these counts. 
///
/// Properties:
/// * [albumsSearched] - Albums the release match looked up: which pressing of a record the library holds, resolved from a barcode or a catalog number. 
/// * [albumsMatched] - Albums it pinned to a release. Searched without matched is a library whose albums carry no identifiers, not a broken pass. 
/// * [artistArtEnriched] - Artists the artwork walk looked at. It reaches every artist by name, so this counts the ones still missing a portrait rather than the ones MusicBrainz matched. 
/// * [artistArtMatched] - Artists some provider answered a picture for.
/// * [trackFieldsEnriched] - Tracks the fields walk looked up, filling tempo, ISRC and composer where they were empty and unlocked. 
/// * [trackFieldsMatched] - Tracks some provider answered for.
/// * [bookFieldsEnriched] - Audiobooks the fields walk looked up, filling publisher, year, description, narrator, subtitle, edition and the identifiers where they were empty and unlocked. 
/// * [bookFieldsMatched] - Audiobooks some provider answered for.
/// * [albumFieldsEnriched] - Albums the fields walk looked up, filling label and year. A year fans out to every track on the album, and is refused where the tracks already disagree. 
/// * [albumFieldsMatched] - Albums some provider answered for.
/// * [tagsWritten] - Files the pass wrote enriched values back into. Zero unless tag write-back is on, which is what makes enrichment survive a rescan. 
/// * [tagsFailed] - Files whose write failed. The catalog kept the values either way.
/// * [tagsUnrepresented] - Files whose format cannot store a key that was filled. Not a failure: the bytes are unchanged and correct. 
/// * [tagsSkipped] - Book parts left unwritten because their book's primary part failed. 
/// * [finishedAt] - When the pass finished.
@BuiltValue()
abstract class EnrichmentLastRun implements Built<EnrichmentLastRun, EnrichmentLastRunBuilder> {
  /// Albums the release match looked up: which pressing of a record the library holds, resolved from a barcode or a catalog number. 
  @BuiltValueField(wireName: r'albumsSearched')
  int get albumsSearched;

  /// Albums it pinned to a release. Searched without matched is a library whose albums carry no identifiers, not a broken pass. 
  @BuiltValueField(wireName: r'albumsMatched')
  int get albumsMatched;

  /// Artists the artwork walk looked at. It reaches every artist by name, so this counts the ones still missing a portrait rather than the ones MusicBrainz matched. 
  @BuiltValueField(wireName: r'artistArtEnriched')
  int get artistArtEnriched;

  /// Artists some provider answered a picture for.
  @BuiltValueField(wireName: r'artistArtMatched')
  int get artistArtMatched;

  /// Tracks the fields walk looked up, filling tempo, ISRC and composer where they were empty and unlocked. 
  @BuiltValueField(wireName: r'trackFieldsEnriched')
  int get trackFieldsEnriched;

  /// Tracks some provider answered for.
  @BuiltValueField(wireName: r'trackFieldsMatched')
  int get trackFieldsMatched;

  /// Audiobooks the fields walk looked up, filling publisher, year, description, narrator, subtitle, edition and the identifiers where they were empty and unlocked. 
  @BuiltValueField(wireName: r'bookFieldsEnriched')
  int get bookFieldsEnriched;

  /// Audiobooks some provider answered for.
  @BuiltValueField(wireName: r'bookFieldsMatched')
  int get bookFieldsMatched;

  /// Albums the fields walk looked up, filling label and year. A year fans out to every track on the album, and is refused where the tracks already disagree. 
  @BuiltValueField(wireName: r'albumFieldsEnriched')
  int get albumFieldsEnriched;

  /// Albums some provider answered for.
  @BuiltValueField(wireName: r'albumFieldsMatched')
  int get albumFieldsMatched;

  /// Files the pass wrote enriched values back into. Zero unless tag write-back is on, which is what makes enrichment survive a rescan. 
  @BuiltValueField(wireName: r'tagsWritten')
  int get tagsWritten;

  /// Files whose write failed. The catalog kept the values either way.
  @BuiltValueField(wireName: r'tagsFailed')
  int get tagsFailed;

  /// Files whose format cannot store a key that was filled. Not a failure: the bytes are unchanged and correct. 
  @BuiltValueField(wireName: r'tagsUnrepresented')
  int get tagsUnrepresented;

  /// Book parts left unwritten because their book's primary part failed. 
  @BuiltValueField(wireName: r'tagsSkipped')
  int get tagsSkipped;

  /// When the pass finished.
  @BuiltValueField(wireName: r'finishedAt')
  DateTime? get finishedAt;

  EnrichmentLastRun._();

  factory EnrichmentLastRun([void updates(EnrichmentLastRunBuilder b)]) = _$EnrichmentLastRun;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentLastRunBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentLastRun> get serializer => _$EnrichmentLastRunSerializer();
}

class _$EnrichmentLastRunSerializer implements PrimitiveSerializer<EnrichmentLastRun> {
  @override
  final Iterable<Type> types = const [EnrichmentLastRun, _$EnrichmentLastRun];

  @override
  final String wireName = r'EnrichmentLastRun';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentLastRun object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'albumsSearched';
    yield serializers.serialize(
      object.albumsSearched,
      specifiedType: const FullType(int),
    );
    yield r'albumsMatched';
    yield serializers.serialize(
      object.albumsMatched,
      specifiedType: const FullType(int),
    );
    yield r'artistArtEnriched';
    yield serializers.serialize(
      object.artistArtEnriched,
      specifiedType: const FullType(int),
    );
    yield r'artistArtMatched';
    yield serializers.serialize(
      object.artistArtMatched,
      specifiedType: const FullType(int),
    );
    yield r'trackFieldsEnriched';
    yield serializers.serialize(
      object.trackFieldsEnriched,
      specifiedType: const FullType(int),
    );
    yield r'trackFieldsMatched';
    yield serializers.serialize(
      object.trackFieldsMatched,
      specifiedType: const FullType(int),
    );
    yield r'bookFieldsEnriched';
    yield serializers.serialize(
      object.bookFieldsEnriched,
      specifiedType: const FullType(int),
    );
    yield r'bookFieldsMatched';
    yield serializers.serialize(
      object.bookFieldsMatched,
      specifiedType: const FullType(int),
    );
    yield r'albumFieldsEnriched';
    yield serializers.serialize(
      object.albumFieldsEnriched,
      specifiedType: const FullType(int),
    );
    yield r'albumFieldsMatched';
    yield serializers.serialize(
      object.albumFieldsMatched,
      specifiedType: const FullType(int),
    );
    yield r'tagsWritten';
    yield serializers.serialize(
      object.tagsWritten,
      specifiedType: const FullType(int),
    );
    yield r'tagsFailed';
    yield serializers.serialize(
      object.tagsFailed,
      specifiedType: const FullType(int),
    );
    yield r'tagsUnrepresented';
    yield serializers.serialize(
      object.tagsUnrepresented,
      specifiedType: const FullType(int),
    );
    yield r'tagsSkipped';
    yield serializers.serialize(
      object.tagsSkipped,
      specifiedType: const FullType(int),
    );
    if (object.finishedAt != null) {
      yield r'finishedAt';
      yield serializers.serialize(
        object.finishedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentLastRun object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentLastRunBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'albumsSearched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.albumsSearched = valueDes;
          break;
        case r'albumsMatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.albumsMatched = valueDes;
          break;
        case r'artistArtEnriched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.artistArtEnriched = valueDes;
          break;
        case r'artistArtMatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.artistArtMatched = valueDes;
          break;
        case r'trackFieldsEnriched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.trackFieldsEnriched = valueDes;
          break;
        case r'trackFieldsMatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.trackFieldsMatched = valueDes;
          break;
        case r'bookFieldsEnriched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bookFieldsEnriched = valueDes;
          break;
        case r'bookFieldsMatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bookFieldsMatched = valueDes;
          break;
        case r'albumFieldsEnriched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.albumFieldsEnriched = valueDes;
          break;
        case r'albumFieldsMatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.albumFieldsMatched = valueDes;
          break;
        case r'tagsWritten':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.tagsWritten = valueDes;
          break;
        case r'tagsFailed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.tagsFailed = valueDes;
          break;
        case r'tagsUnrepresented':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.tagsUnrepresented = valueDes;
          break;
        case r'tagsSkipped':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.tagsSkipped = valueDes;
          break;
        case r'finishedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.finishedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentLastRun deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentLastRunBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

