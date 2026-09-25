//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_last_run.g.dart';

/// What the most recent finished pass did, every tally it keeps; absent until one has finished. Each walk counts what it looked up and what something answered for. 
///
/// Properties:
/// * [artistsEnriched] - Artists the MusicBrainz identity walk looked up.
/// * [artistsMatched] - Artists it resolved.
/// * [releaseGroupsEnriched] - Release groups the identity walk looked up.
/// * [releaseGroupsMatched] - Release groups it resolved.
/// * [albumsSearched] - Albums the release match looked up: which pressing of a record the library holds, resolved from a barcode or a catalog number. 
/// * [albumsMatched] - Albums it pinned to a release. Searched without matched is a library whose albums carry no identifiers, not a broken pass. 
/// * [booksEnriched] - Audiobooks the identity walk looked up.
/// * [booksMatched] - Audiobooks it resolved.
/// * [lyricsEnriched] - Tracks the lyrics walk looked up.
/// * [lyricsMatched] - Tracks some provider answered lyrics for.
/// * [auxArtEnriched] - Release groups the auxiliary-art backfill looked at: a front settled, a back, disc, booklet or background slot empty. 
/// * [auxArtMatched] - Release groups some provider answered for.
/// * [artistArtEnriched] - Artists the artwork walk looked at. It reaches every artist by name, so this counts the ones still missing a portrait rather than the ones MusicBrainz matched. 
/// * [artistArtMatched] - Artists some provider answered a picture for.
/// * [albumArtEnriched] - Albums the album-art backfill looked at: ones that resolve no front cover at all, asked about by their own identifiers. 
/// * [albumArtMatched] - Albums some provider answered for.
/// * [trackFieldsEnriched] - Tracks the fields walk looked up, filling tempo, ISRC and composer where they were empty and unlocked. 
/// * [trackFieldsMatched] - Tracks some provider answered for.
/// * [bookFieldsEnriched] - Audiobooks the fields walk looked up, filling publisher, year, description, narrator, subtitle, edition and the identifiers where they were empty and unlocked. 
/// * [bookFieldsMatched] - Audiobooks some provider answered for.
/// * [albumFieldsEnriched] - Albums the fields walk looked up, filling label and year. A year fans out to every track on the album, and is refused where the tracks already disagree. 
/// * [albumFieldsMatched] - Albums some provider answered for.
/// * [retried] - Targets re-asked because their earlier miss had outlived the retry window. The walks above count them too. 
/// * [artFetched] - Front covers downloaded and handed to the catalog, across every walk. The catalog still fills only empty, unlocked slots. 
/// * [auxArtFetched] - Back, disc, booklet and background images, counted the same way.
/// * [artReused] - Album fronts taken from the release group's picture, on a provider's word that it is that pressing's own; nothing was downloaded for them. 
/// * [tagsWritten] - Files the pass wrote enriched values back into. Zero unless tag write-back is on, which is what makes enrichment survive a rescan. 
/// * [tagsFailed] - Files whose write failed. The catalog kept the values either way.
/// * [tagsUnrepresented] - Files whose format cannot store a key that was filled. Not a failure: the bytes are unchanged and correct. 
/// * [tagsSkipped] - Book parts left unwritten because their book's primary part failed. 
/// * [finishedAt] - When the pass finished.
@BuiltValue()
abstract class EnrichmentLastRun implements Built<EnrichmentLastRun, EnrichmentLastRunBuilder> {
  /// Artists the MusicBrainz identity walk looked up.
  @BuiltValueField(wireName: r'artistsEnriched')
  int get artistsEnriched;

  /// Artists it resolved.
  @BuiltValueField(wireName: r'artistsMatched')
  int get artistsMatched;

  /// Release groups the identity walk looked up.
  @BuiltValueField(wireName: r'releaseGroupsEnriched')
  int get releaseGroupsEnriched;

  /// Release groups it resolved.
  @BuiltValueField(wireName: r'releaseGroupsMatched')
  int get releaseGroupsMatched;

  /// Albums the release match looked up: which pressing of a record the library holds, resolved from a barcode or a catalog number. 
  @BuiltValueField(wireName: r'albumsSearched')
  int get albumsSearched;

  /// Albums it pinned to a release. Searched without matched is a library whose albums carry no identifiers, not a broken pass. 
  @BuiltValueField(wireName: r'albumsMatched')
  int get albumsMatched;

  /// Audiobooks the identity walk looked up.
  @BuiltValueField(wireName: r'booksEnriched')
  int get booksEnriched;

  /// Audiobooks it resolved.
  @BuiltValueField(wireName: r'booksMatched')
  int get booksMatched;

  /// Tracks the lyrics walk looked up.
  @BuiltValueField(wireName: r'lyricsEnriched')
  int get lyricsEnriched;

  /// Tracks some provider answered lyrics for.
  @BuiltValueField(wireName: r'lyricsMatched')
  int get lyricsMatched;

  /// Release groups the auxiliary-art backfill looked at: a front settled, a back, disc, booklet or background slot empty. 
  @BuiltValueField(wireName: r'auxArtEnriched')
  int get auxArtEnriched;

  /// Release groups some provider answered for.
  @BuiltValueField(wireName: r'auxArtMatched')
  int get auxArtMatched;

  /// Artists the artwork walk looked at. It reaches every artist by name, so this counts the ones still missing a portrait rather than the ones MusicBrainz matched. 
  @BuiltValueField(wireName: r'artistArtEnriched')
  int get artistArtEnriched;

  /// Artists some provider answered a picture for.
  @BuiltValueField(wireName: r'artistArtMatched')
  int get artistArtMatched;

  /// Albums the album-art backfill looked at: ones that resolve no front cover at all, asked about by their own identifiers. 
  @BuiltValueField(wireName: r'albumArtEnriched')
  int get albumArtEnriched;

  /// Albums some provider answered for.
  @BuiltValueField(wireName: r'albumArtMatched')
  int get albumArtMatched;

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

  /// Targets re-asked because their earlier miss had outlived the retry window. The walks above count them too. 
  @BuiltValueField(wireName: r'retried')
  int get retried;

  /// Front covers downloaded and handed to the catalog, across every walk. The catalog still fills only empty, unlocked slots. 
  @BuiltValueField(wireName: r'artFetched')
  int get artFetched;

  /// Back, disc, booklet and background images, counted the same way.
  @BuiltValueField(wireName: r'auxArtFetched')
  int get auxArtFetched;

  /// Album fronts taken from the release group's picture, on a provider's word that it is that pressing's own; nothing was downloaded for them. 
  @BuiltValueField(wireName: r'artReused')
  int get artReused;

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
    yield r'artistsEnriched';
    yield serializers.serialize(
      object.artistsEnriched,
      specifiedType: const FullType(int),
    );
    yield r'artistsMatched';
    yield serializers.serialize(
      object.artistsMatched,
      specifiedType: const FullType(int),
    );
    yield r'releaseGroupsEnriched';
    yield serializers.serialize(
      object.releaseGroupsEnriched,
      specifiedType: const FullType(int),
    );
    yield r'releaseGroupsMatched';
    yield serializers.serialize(
      object.releaseGroupsMatched,
      specifiedType: const FullType(int),
    );
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
    yield r'booksEnriched';
    yield serializers.serialize(
      object.booksEnriched,
      specifiedType: const FullType(int),
    );
    yield r'booksMatched';
    yield serializers.serialize(
      object.booksMatched,
      specifiedType: const FullType(int),
    );
    yield r'lyricsEnriched';
    yield serializers.serialize(
      object.lyricsEnriched,
      specifiedType: const FullType(int),
    );
    yield r'lyricsMatched';
    yield serializers.serialize(
      object.lyricsMatched,
      specifiedType: const FullType(int),
    );
    yield r'auxArtEnriched';
    yield serializers.serialize(
      object.auxArtEnriched,
      specifiedType: const FullType(int),
    );
    yield r'auxArtMatched';
    yield serializers.serialize(
      object.auxArtMatched,
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
    yield r'albumArtEnriched';
    yield serializers.serialize(
      object.albumArtEnriched,
      specifiedType: const FullType(int),
    );
    yield r'albumArtMatched';
    yield serializers.serialize(
      object.albumArtMatched,
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
    yield r'retried';
    yield serializers.serialize(
      object.retried,
      specifiedType: const FullType(int),
    );
    yield r'artFetched';
    yield serializers.serialize(
      object.artFetched,
      specifiedType: const FullType(int),
    );
    yield r'auxArtFetched';
    yield serializers.serialize(
      object.auxArtFetched,
      specifiedType: const FullType(int),
    );
    yield r'artReused';
    yield serializers.serialize(
      object.artReused,
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
        case r'artistsEnriched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.artistsEnriched = valueDes;
          break;
        case r'artistsMatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.artistsMatched = valueDes;
          break;
        case r'releaseGroupsEnriched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.releaseGroupsEnriched = valueDes;
          break;
        case r'releaseGroupsMatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.releaseGroupsMatched = valueDes;
          break;
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
        case r'booksEnriched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.booksEnriched = valueDes;
          break;
        case r'booksMatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.booksMatched = valueDes;
          break;
        case r'lyricsEnriched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.lyricsEnriched = valueDes;
          break;
        case r'lyricsMatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.lyricsMatched = valueDes;
          break;
        case r'auxArtEnriched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.auxArtEnriched = valueDes;
          break;
        case r'auxArtMatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.auxArtMatched = valueDes;
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
        case r'albumArtEnriched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.albumArtEnriched = valueDes;
          break;
        case r'albumArtMatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.albumArtMatched = valueDes;
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
        case r'retried':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.retried = valueDes;
          break;
        case r'artFetched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.artFetched = valueDes;
          break;
        case r'auxArtFetched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.auxArtFetched = valueDes;
          break;
        case r'artReused':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.artReused = valueDes;
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
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
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


