//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'entity_card.g.dart';

/// Display facts for one entity: what a card draws. Artwork is not a field - `/items/{pid}/art` takes every prefix this endpoint answers for except `rg-`, which statically has none, so a client builds the URL from the pid rather than being handed it. 
///
/// Properties:
/// * [pid] - The type-prefixed PID this card answers for.
/// * [kind] - What the card is about, which is what a tap opens.
/// * [title] - Display title - the album, artist, show, or book name.
/// * [artist] - The context line: an album's or book's artist, a show's author. Absent for an artist (whose title is the name) and wherever the catalog has none. 
/// * [year] - Release year, where the entity carries one.
/// * [itemCount] - Member items: an album's tracks, a playlist's entries, a show's episodes, an artist's tracks. Absent where counting costs a read the card does not need. 
@BuiltValue()
abstract class EntityCard implements Built<EntityCard, EntityCardBuilder> {
  /// The type-prefixed PID this card answers for.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// What the card is about, which is what a tap opens.
  @BuiltValueField(wireName: r'kind')
  EntityCardKindEnum get kind;
  // enum kindEnum {  album,  artist,  release-group,  playlist,  podcast,  book,  };

  /// Display title - the album, artist, show, or book name.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// The context line: an album's or book's artist, a show's author. Absent for an artist (whose title is the name) and wherever the catalog has none. 
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// Release year, where the entity carries one.
  @BuiltValueField(wireName: r'year')
  int? get year;

  /// Member items: an album's tracks, a playlist's entries, a show's episodes, an artist's tracks. Absent where counting costs a read the card does not need. 
  @BuiltValueField(wireName: r'itemCount')
  int? get itemCount;

  EntityCard._();

  factory EntityCard([void updates(EntityCardBuilder b)]) = _$EntityCard;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EntityCardBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EntityCard> get serializer => _$EntityCardSerializer();
}

class _$EntityCardSerializer implements PrimitiveSerializer<EntityCard> {
  @override
  final Iterable<Type> types = const [EntityCard, _$EntityCard];

  @override
  final String wireName = r'EntityCard';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EntityCard object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(EntityCardKindEnum),
    );
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    if (object.year != null) {
      yield r'year';
      yield serializers.serialize(
        object.year,
        specifiedType: const FullType(int),
      );
    }
    if (object.itemCount != null) {
      yield r'itemCount';
      yield serializers.serialize(
        object.itemCount,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EntityCard object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EntityCardBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EntityCardKindEnum),
          ) as EntityCardKindEnum;
          result.kind = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'artist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artist = valueDes;
          break;
        case r'year':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.year = valueDes;
          break;
        case r'itemCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.itemCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EntityCard deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EntityCardBuilder();
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

class EntityCardKindEnum extends EnumClass {

  /// What the card is about, which is what a tap opens.
  @BuiltValueEnumConst(wireName: r'album')
  static const EntityCardKindEnum album = _$entityCardKindEnum_album;
  /// What the card is about, which is what a tap opens.
  @BuiltValueEnumConst(wireName: r'artist')
  static const EntityCardKindEnum artist = _$entityCardKindEnum_artist;
  /// What the card is about, which is what a tap opens.
  @BuiltValueEnumConst(wireName: r'release-group')
  static const EntityCardKindEnum releaseGroup = _$entityCardKindEnum_releaseGroup;
  /// What the card is about, which is what a tap opens.
  @BuiltValueEnumConst(wireName: r'playlist')
  static const EntityCardKindEnum playlist = _$entityCardKindEnum_playlist;
  /// What the card is about, which is what a tap opens.
  @BuiltValueEnumConst(wireName: r'podcast')
  static const EntityCardKindEnum podcast = _$entityCardKindEnum_podcast;
  /// What the card is about, which is what a tap opens.
  @BuiltValueEnumConst(wireName: r'book')
  static const EntityCardKindEnum book = _$entityCardKindEnum_book;

  static Serializer<EntityCardKindEnum> get serializer => _$entityCardKindEnumSerializer;

  const EntityCardKindEnum._(String name): super(name);

  static BuiltSet<EntityCardKindEnum> get values => _$entityCardKindEnumValues;
  static EntityCardKindEnum valueOf(String name) => _$entityCardKindEnumValueOf(name);
}

