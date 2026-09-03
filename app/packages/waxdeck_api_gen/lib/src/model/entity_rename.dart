//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'entity_rename.g.dart';

/// An entity rename.
///
/// Properties:
/// * [fields] - The keying fields to move the entity onto. An album takes `album`, `album_artist`, and `year`; a release group takes `album` and `album_artist`; an artist takes `name`. A field outside its rung's vocabulary, or a name renamed to nothing, is refused. 
/// * [writeBack] - Also write the new values into every member file's tags (`ALBUM`, `ALBUMARTIST`, `DATE`, `ARTIST`, plus the moved contributor credits). 
/// * [lock] - Lock each renamed field on every member, and each moved credit's own `credit.<role>` lock. 
/// * [force] - Override a locked keying field or credit.
@BuiltValue()
abstract class EntityRename implements Built<EntityRename, EntityRenameBuilder> {
  /// The keying fields to move the entity onto. An album takes `album`, `album_artist`, and `year`; a release group takes `album` and `album_artist`; an artist takes `name`. A field outside its rung's vocabulary, or a name renamed to nothing, is refused. 
  @BuiltValueField(wireName: r'fields')
  BuiltMap<String, String> get fields;

  /// Also write the new values into every member file's tags (`ALBUM`, `ALBUMARTIST`, `DATE`, `ARTIST`, plus the moved contributor credits). 
  @BuiltValueField(wireName: r'writeBack')
  bool? get writeBack;

  /// Lock each renamed field on every member, and each moved credit's own `credit.<role>` lock. 
  @BuiltValueField(wireName: r'lock')
  bool? get lock;

  /// Override a locked keying field or credit.
  @BuiltValueField(wireName: r'force')
  bool? get force;

  EntityRename._();

  factory EntityRename([void updates(EntityRenameBuilder b)]) = _$EntityRename;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EntityRenameBuilder b) => b
      ..writeBack = false
      ..lock = true
      ..force = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<EntityRename> get serializer => _$EntityRenameSerializer();
}

class _$EntityRenameSerializer implements PrimitiveSerializer<EntityRename> {
  @override
  final Iterable<Type> types = const [EntityRename, _$EntityRename];

  @override
  final String wireName = r'EntityRename';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EntityRename object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'fields';
    yield serializers.serialize(
      object.fields,
      specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
    );
    if (object.writeBack != null) {
      yield r'writeBack';
      yield serializers.serialize(
        object.writeBack,
        specifiedType: const FullType(bool),
      );
    }
    if (object.lock != null) {
      yield r'lock';
      yield serializers.serialize(
        object.lock,
        specifiedType: const FullType(bool),
      );
    }
    if (object.force != null) {
      yield r'force';
      yield serializers.serialize(
        object.force,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EntityRename object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EntityRenameBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'fields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
          ) as BuiltMap<String, String>;
          result.fields.replace(valueDes);
          break;
        case r'writeBack':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.writeBack = valueDes;
          break;
        case r'lock':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.lock = valueDes;
          break;
        case r'force':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.force = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EntityRename deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EntityRenameBuilder();
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

