//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'catalog_consistency.g.dart';

/// The catalog's derived data against a fresh recompute from its own rows. Each count is rows that disagree, or unused rows a repair deletes. 
///
/// Properties:
/// * [itemsMissingFromSearch] - Present items with no search index row, which search cannot find. 
/// * [orphanSearchRows] - Search index rows whose item is gone.
/// * [artistRollupDrift] - Artists whose stored totals differ from a recount of their items. 
/// * [genreRollupDrift] - Genres whose stored totals differ from a recount of their items. 
/// * [releaseGroupRollupDrift] - Release groups whose stored totals differ from a recount of their albums. 
/// * [sortKeyDrift] - Names whose stored sort key is not the one the catalog generates for them now, so they list out of place. 
/// * [bookDurationDrift] - Books whose stored length differs from the sum of their parts. 
/// * [bookIsbnKeyDrift] - Books whose stored ISBN match key is not the one their ISBN gives. 
/// * [albumYearDrift] - Albums whose year is not the one their tracks give.
/// * [releaseYearDrift] - Items whose release year differs from their track's or book's year. 
/// * [playlistPositionDrift] - Static playlists whose entry positions are not numbered from 0 without gaps. Their order reads the same either way, so they do not count against `consistent`. 
/// * [orphanArtSources] - Stored images no entity uses.
/// * [orphanThumbnails] - Cached thumbnails of images no entity uses.
/// * [orphanTagProvenance] - Custom-tag edit records under a key the catalog has since reserved, which nothing can read, edit or unlock. 
/// * [strandedTagRows] - Custom-tag values and locks under a key the catalog no longer accepts, and tag writes owed under a key no file can carry. 
/// * [consistent] - True when every count is zero but `playlistPositionDrift` and the four unused-row counts (`orphanArtSources`, `orphanThumbnails`, `orphanTagProvenance`, `strandedTagRows`). 
/// * [reclaimable] - True when any of the four unused-row counts is above zero: rows a repair deletes, which do not count against `consistent`. 
@BuiltValue()
abstract class CatalogConsistency implements Built<CatalogConsistency, CatalogConsistencyBuilder> {
  /// Present items with no search index row, which search cannot find. 
  @BuiltValueField(wireName: r'itemsMissingFromSearch')
  int get itemsMissingFromSearch;

  /// Search index rows whose item is gone.
  @BuiltValueField(wireName: r'orphanSearchRows')
  int get orphanSearchRows;

  /// Artists whose stored totals differ from a recount of their items. 
  @BuiltValueField(wireName: r'artistRollupDrift')
  int get artistRollupDrift;

  /// Genres whose stored totals differ from a recount of their items. 
  @BuiltValueField(wireName: r'genreRollupDrift')
  int get genreRollupDrift;

  /// Release groups whose stored totals differ from a recount of their albums. 
  @BuiltValueField(wireName: r'releaseGroupRollupDrift')
  int get releaseGroupRollupDrift;

  /// Names whose stored sort key is not the one the catalog generates for them now, so they list out of place. 
  @BuiltValueField(wireName: r'sortKeyDrift')
  int get sortKeyDrift;

  /// Books whose stored length differs from the sum of their parts. 
  @BuiltValueField(wireName: r'bookDurationDrift')
  int get bookDurationDrift;

  /// Books whose stored ISBN match key is not the one their ISBN gives. 
  @BuiltValueField(wireName: r'bookIsbnKeyDrift')
  int get bookIsbnKeyDrift;

  /// Albums whose year is not the one their tracks give.
  @BuiltValueField(wireName: r'albumYearDrift')
  int get albumYearDrift;

  /// Items whose release year differs from their track's or book's year. 
  @BuiltValueField(wireName: r'releaseYearDrift')
  int get releaseYearDrift;

  /// Static playlists whose entry positions are not numbered from 0 without gaps. Their order reads the same either way, so they do not count against `consistent`. 
  @BuiltValueField(wireName: r'playlistPositionDrift')
  int get playlistPositionDrift;

  /// Stored images no entity uses.
  @BuiltValueField(wireName: r'orphanArtSources')
  int get orphanArtSources;

  /// Cached thumbnails of images no entity uses.
  @BuiltValueField(wireName: r'orphanThumbnails')
  int get orphanThumbnails;

  /// Custom-tag edit records under a key the catalog has since reserved, which nothing can read, edit or unlock. 
  @BuiltValueField(wireName: r'orphanTagProvenance')
  int get orphanTagProvenance;

  /// Custom-tag values and locks under a key the catalog no longer accepts, and tag writes owed under a key no file can carry. 
  @BuiltValueField(wireName: r'strandedTagRows')
  int get strandedTagRows;

  /// True when every count is zero but `playlistPositionDrift` and the four unused-row counts (`orphanArtSources`, `orphanThumbnails`, `orphanTagProvenance`, `strandedTagRows`). 
  @BuiltValueField(wireName: r'consistent')
  bool get consistent;

  /// True when any of the four unused-row counts is above zero: rows a repair deletes, which do not count against `consistent`. 
  @BuiltValueField(wireName: r'reclaimable')
  bool get reclaimable;

  CatalogConsistency._();

  factory CatalogConsistency([void updates(CatalogConsistencyBuilder b)]) = _$CatalogConsistency;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CatalogConsistencyBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CatalogConsistency> get serializer => _$CatalogConsistencySerializer();
}

class _$CatalogConsistencySerializer implements PrimitiveSerializer<CatalogConsistency> {
  @override
  final Iterable<Type> types = const [CatalogConsistency, _$CatalogConsistency];

  @override
  final String wireName = r'CatalogConsistency';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CatalogConsistency object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'itemsMissingFromSearch';
    yield serializers.serialize(
      object.itemsMissingFromSearch,
      specifiedType: const FullType(int),
    );
    yield r'orphanSearchRows';
    yield serializers.serialize(
      object.orphanSearchRows,
      specifiedType: const FullType(int),
    );
    yield r'artistRollupDrift';
    yield serializers.serialize(
      object.artistRollupDrift,
      specifiedType: const FullType(int),
    );
    yield r'genreRollupDrift';
    yield serializers.serialize(
      object.genreRollupDrift,
      specifiedType: const FullType(int),
    );
    yield r'releaseGroupRollupDrift';
    yield serializers.serialize(
      object.releaseGroupRollupDrift,
      specifiedType: const FullType(int),
    );
    yield r'sortKeyDrift';
    yield serializers.serialize(
      object.sortKeyDrift,
      specifiedType: const FullType(int),
    );
    yield r'bookDurationDrift';
    yield serializers.serialize(
      object.bookDurationDrift,
      specifiedType: const FullType(int),
    );
    yield r'bookIsbnKeyDrift';
    yield serializers.serialize(
      object.bookIsbnKeyDrift,
      specifiedType: const FullType(int),
    );
    yield r'albumYearDrift';
    yield serializers.serialize(
      object.albumYearDrift,
      specifiedType: const FullType(int),
    );
    yield r'releaseYearDrift';
    yield serializers.serialize(
      object.releaseYearDrift,
      specifiedType: const FullType(int),
    );
    yield r'playlistPositionDrift';
    yield serializers.serialize(
      object.playlistPositionDrift,
      specifiedType: const FullType(int),
    );
    yield r'orphanArtSources';
    yield serializers.serialize(
      object.orphanArtSources,
      specifiedType: const FullType(int),
    );
    yield r'orphanThumbnails';
    yield serializers.serialize(
      object.orphanThumbnails,
      specifiedType: const FullType(int),
    );
    yield r'orphanTagProvenance';
    yield serializers.serialize(
      object.orphanTagProvenance,
      specifiedType: const FullType(int),
    );
    yield r'strandedTagRows';
    yield serializers.serialize(
      object.strandedTagRows,
      specifiedType: const FullType(int),
    );
    yield r'consistent';
    yield serializers.serialize(
      object.consistent,
      specifiedType: const FullType(bool),
    );
    yield r'reclaimable';
    yield serializers.serialize(
      object.reclaimable,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CatalogConsistency object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CatalogConsistencyBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'itemsMissingFromSearch':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.itemsMissingFromSearch = valueDes;
          break;
        case r'orphanSearchRows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.orphanSearchRows = valueDes;
          break;
        case r'artistRollupDrift':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.artistRollupDrift = valueDes;
          break;
        case r'genreRollupDrift':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.genreRollupDrift = valueDes;
          break;
        case r'releaseGroupRollupDrift':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.releaseGroupRollupDrift = valueDes;
          break;
        case r'sortKeyDrift':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sortKeyDrift = valueDes;
          break;
        case r'bookDurationDrift':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bookDurationDrift = valueDes;
          break;
        case r'bookIsbnKeyDrift':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bookIsbnKeyDrift = valueDes;
          break;
        case r'albumYearDrift':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.albumYearDrift = valueDes;
          break;
        case r'releaseYearDrift':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.releaseYearDrift = valueDes;
          break;
        case r'playlistPositionDrift':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.playlistPositionDrift = valueDes;
          break;
        case r'orphanArtSources':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.orphanArtSources = valueDes;
          break;
        case r'orphanThumbnails':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.orphanThumbnails = valueDes;
          break;
        case r'orphanTagProvenance':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.orphanTagProvenance = valueDes;
          break;
        case r'strandedTagRows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.strandedTagRows = valueDes;
          break;
        case r'consistent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.consistent = valueDes;
          break;
        case r'reclaimable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.reclaimable = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CatalogConsistency deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CatalogConsistencyBuilder();
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


