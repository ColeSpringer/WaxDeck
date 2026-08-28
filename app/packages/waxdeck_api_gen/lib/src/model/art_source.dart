//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'art_source.g.dart';

/// Where the picture a caller is about to draw came from, so a surface that shows a cover large enough to carry a caption can say so. Reported on the entity detail reads (which already carry the identity the cover belongs to) rather than on list rows: a grid thumbnail has no room for a mark, and putting this on every summary row would cost a lookup per row for a caption nothing draws.  This describes the picture that a front-cover resolve actually answers with, which for an album with no durable cover of its own is a member track's - reported honestly as that track's source, with `derived` marking that the album did not choose it. 
///
/// Properties:
/// * [source_] - The producer: `tag` (the file's own embedded cover), `sidecar` (a cover image beside the audio), `user` (set through the curation surface), `enrichment` (fetched from a metadata provider, named in `provider`), `feed` (a podcast feed's image, or a radio station's own announcement), or `generated` (composed by the server from what the catalog already holds, which is what a playlist mosaic is - nobody chose it). A string, not a closed enum: treat an unknown value as unattributed and draw nothing. 
/// * [provider] - The provider that supplied an `enrichment` cover, as an id (`deezer`, `coverartarchive`, `fanarttv`). Empty for every other source. 
/// * [sourceUrl] - Where the bytes were fetched from, for a cover that came off the network (`enrichment`, `feed`). Empty otherwise.  Redacted the way `ItemAcquisition.sourceUrl` is, and for the same reason - these reads answer everyone who can see the item while the stored value is verbatim: `http`/`https` only, reduced to scheme, host and path. A `feed` cover on a show with stored credentials is withheld entirely rather than redacted, because its address is minted from the same document the credentials open. So this identifies where a picture came from; it is not a URL to re-fetch it by. 
/// * [level] - Which rung of the fallback chain answered: `track`, `book`, `episode`, `album`, `artist`, `release_group`, `genre`, `podcast`, or `playlist`. Absent where there is no chain (radio, which resolves nothing from the catalog). Open set; a client that does not recognise a value should name no rung rather than guess. 
/// * [derived] - True when the answering level holds no cover of its own and the picture came from a member instead - an album showing one of its tracks' covers, which is the ordinary case for an album nobody has given a durable cover. `source` is that member's, so this is what stops a caption reading as though the album made the choice. Absent means the same as false. 
/// * [updatedAt] - When this attachment was last written.
@BuiltValue()
abstract class ArtSource implements Built<ArtSource, ArtSourceBuilder> {
  /// The producer: `tag` (the file's own embedded cover), `sidecar` (a cover image beside the audio), `user` (set through the curation surface), `enrichment` (fetched from a metadata provider, named in `provider`), `feed` (a podcast feed's image, or a radio station's own announcement), or `generated` (composed by the server from what the catalog already holds, which is what a playlist mosaic is - nobody chose it). A string, not a closed enum: treat an unknown value as unattributed and draw nothing. 
  @BuiltValueField(wireName: r'source')
  String get source_;

  /// The provider that supplied an `enrichment` cover, as an id (`deezer`, `coverartarchive`, `fanarttv`). Empty for every other source. 
  @BuiltValueField(wireName: r'provider')
  String? get provider;

  /// Where the bytes were fetched from, for a cover that came off the network (`enrichment`, `feed`). Empty otherwise.  Redacted the way `ItemAcquisition.sourceUrl` is, and for the same reason - these reads answer everyone who can see the item while the stored value is verbatim: `http`/`https` only, reduced to scheme, host and path. A `feed` cover on a show with stored credentials is withheld entirely rather than redacted, because its address is minted from the same document the credentials open. So this identifies where a picture came from; it is not a URL to re-fetch it by. 
  @BuiltValueField(wireName: r'sourceUrl')
  String? get sourceUrl;

  /// Which rung of the fallback chain answered: `track`, `book`, `episode`, `album`, `artist`, `release_group`, `genre`, `podcast`, or `playlist`. Absent where there is no chain (radio, which resolves nothing from the catalog). Open set; a client that does not recognise a value should name no rung rather than guess. 
  @BuiltValueField(wireName: r'level')
  String? get level;

  /// True when the answering level holds no cover of its own and the picture came from a member instead - an album showing one of its tracks' covers, which is the ordinary case for an album nobody has given a durable cover. `source` is that member's, so this is what stops a caption reading as though the album made the choice. Absent means the same as false. 
  @BuiltValueField(wireName: r'derived')
  bool? get derived;

  /// When this attachment was last written.
  @BuiltValueField(wireName: r'updatedAt')
  DateTime? get updatedAt;

  ArtSource._();

  factory ArtSource([void updates(ArtSourceBuilder b)]) = _$ArtSource;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ArtSourceBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ArtSource> get serializer => _$ArtSourceSerializer();
}

class _$ArtSourceSerializer implements PrimitiveSerializer<ArtSource> {
  @override
  final Iterable<Type> types = const [ArtSource, _$ArtSource];

  @override
  final String wireName = r'ArtSource';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ArtSource object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(String),
    );
    if (object.provider != null) {
      yield r'provider';
      yield serializers.serialize(
        object.provider,
        specifiedType: const FullType(String),
      );
    }
    if (object.sourceUrl != null) {
      yield r'sourceUrl';
      yield serializers.serialize(
        object.sourceUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.level != null) {
      yield r'level';
      yield serializers.serialize(
        object.level,
        specifiedType: const FullType(String),
      );
    }
    if (object.derived != null) {
      yield r'derived';
      yield serializers.serialize(
        object.derived,
        specifiedType: const FullType(bool),
      );
    }
    if (object.updatedAt != null) {
      yield r'updatedAt';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ArtSource object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ArtSourceBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.source_ = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.provider = valueDes;
          break;
        case r'sourceUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceUrl = valueDes;
          break;
        case r'level':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.level = valueDes;
          break;
        case r'derived':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.derived = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ArtSource deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ArtSourceBuilder();
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

