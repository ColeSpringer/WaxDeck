//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'entity_fold.g.dart';

/// One name folded into an entity: a file whose tags still spell it files under that entity. 
///
/// Properties:
/// * [entityType] - `album`, `artist`, `genre`, `release-group`, or `series`.
/// * [key] - The folded name as the catalog matches it, the handle `POST /library/folds/unfold` takes. Opaque: it can hold separator characters. 
/// * [spelling] - The key as a person reads it: the name lower-cased, with accents and punctuation folded away; an album's or a release group's as its artist and title joined by ` - `; one keyed by a MusicBrainz id as `MusicBrainz` and the id. Two folds can spell alike, and `facet`, or `folder` and `library`, then tell them apart, or `createdAt` for album folds no file places. 
/// * [facet] - A genre fold's facet, `genre` or `mood`: one name folds apart in each. 
/// * [folder] - An album fold's folder as a path within its library, read off a file of the album that sits in it: copies of one release in different folders fold apart. Absent for an album at the top of its library, for one known by its own MusicBrainz id, and for a fold no present file of its album places (its files have left the folder, or two folders fold to its key alike); `createdAt` still tells such folds apart when they were folded at different times. 
/// * [library_] - The name of the library holding an album fold's folder, given whenever the fold is placed: with `folder`, or alone for an album at the top of its library. 
/// * [entityPid] - The entity the name files under: prefixed (`ar-`, `al-`, `rg-`, `sr-`) where the type has a prefix, and a genre's bare, as the genre listing takes it. 
/// * [entityName] - The entity's display name.
/// * [createdAt] - When the name was folded.
@BuiltValue()
abstract class EntityFold implements Built<EntityFold, EntityFoldBuilder> {
  /// `album`, `artist`, `genre`, `release-group`, or `series`.
  @BuiltValueField(wireName: r'entityType')
  String get entityType;

  /// The folded name as the catalog matches it, the handle `POST /library/folds/unfold` takes. Opaque: it can hold separator characters. 
  @BuiltValueField(wireName: r'key')
  String get key;

  /// The key as a person reads it: the name lower-cased, with accents and punctuation folded away; an album's or a release group's as its artist and title joined by ` - `; one keyed by a MusicBrainz id as `MusicBrainz` and the id. Two folds can spell alike, and `facet`, or `folder` and `library`, then tell them apart, or `createdAt` for album folds no file places. 
  @BuiltValueField(wireName: r'spelling')
  String get spelling;

  /// A genre fold's facet, `genre` or `mood`: one name folds apart in each. 
  @BuiltValueField(wireName: r'facet')
  String? get facet;

  /// An album fold's folder as a path within its library, read off a file of the album that sits in it: copies of one release in different folders fold apart. Absent for an album at the top of its library, for one known by its own MusicBrainz id, and for a fold no present file of its album places (its files have left the folder, or two folders fold to its key alike); `createdAt` still tells such folds apart when they were folded at different times. 
  @BuiltValueField(wireName: r'folder')
  String? get folder;

  /// The name of the library holding an album fold's folder, given whenever the fold is placed: with `folder`, or alone for an album at the top of its library. 
  @BuiltValueField(wireName: r'library')
  String? get library_;

  /// The entity the name files under: prefixed (`ar-`, `al-`, `rg-`, `sr-`) where the type has a prefix, and a genre's bare, as the genre listing takes it. 
  @BuiltValueField(wireName: r'entityPid')
  String get entityPid;

  /// The entity's display name.
  @BuiltValueField(wireName: r'entityName')
  String get entityName;

  /// When the name was folded.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  EntityFold._();

  factory EntityFold([void updates(EntityFoldBuilder b)]) = _$EntityFold;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EntityFoldBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EntityFold> get serializer => _$EntityFoldSerializer();
}

class _$EntityFoldSerializer implements PrimitiveSerializer<EntityFold> {
  @override
  final Iterable<Type> types = const [EntityFold, _$EntityFold];

  @override
  final String wireName = r'EntityFold';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EntityFold object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entityType';
    yield serializers.serialize(
      object.entityType,
      specifiedType: const FullType(String),
    );
    yield r'key';
    yield serializers.serialize(
      object.key,
      specifiedType: const FullType(String),
    );
    yield r'spelling';
    yield serializers.serialize(
      object.spelling,
      specifiedType: const FullType(String),
    );
    if (object.facet != null) {
      yield r'facet';
      yield serializers.serialize(
        object.facet,
        specifiedType: const FullType(String),
      );
    }
    if (object.folder != null) {
      yield r'folder';
      yield serializers.serialize(
        object.folder,
        specifiedType: const FullType(String),
      );
    }
    if (object.library_ != null) {
      yield r'library';
      yield serializers.serialize(
        object.library_,
        specifiedType: const FullType(String),
      );
    }
    yield r'entityPid';
    yield serializers.serialize(
      object.entityPid,
      specifiedType: const FullType(String),
    );
    yield r'entityName';
    yield serializers.serialize(
      object.entityName,
      specifiedType: const FullType(String),
    );
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EntityFold object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EntityFoldBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entityType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.entityType = valueDes;
          break;
        case r'key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.key = valueDes;
          break;
        case r'spelling':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.spelling = valueDes;
          break;
        case r'facet':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.facet = valueDes;
          break;
        case r'folder':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.folder = valueDes;
          break;
        case r'library':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.library_ = valueDes;
          break;
        case r'entityPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.entityPid = valueDes;
          break;
        case r'entityName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.entityName = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EntityFold deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EntityFoldBuilder();
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


