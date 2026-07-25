//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'genre_node.g.dart';

/// One genre in the canonical vocabulary.
///
/// Properties:
/// * [name] - The canonical display spelling. Every surface shows this.
/// * [parent] - The top-level genre this one groups under, by canonical name. Absent or empty for a top-level genre. The tree is two levels deep: a parent may not itself have one. 
/// * [aliases] - The spellings that resolve to this genre. Case, diacritics, and punctuation already fold, so list only what folding cannot reach. 
@BuiltValue()
abstract class GenreNode implements Built<GenreNode, GenreNodeBuilder> {
  /// The canonical display spelling. Every surface shows this.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// The top-level genre this one groups under, by canonical name. Absent or empty for a top-level genre. The tree is two levels deep: a parent may not itself have one. 
  @BuiltValueField(wireName: r'parent')
  String? get parent;

  /// The spellings that resolve to this genre. Case, diacritics, and punctuation already fold, so list only what folding cannot reach. 
  @BuiltValueField(wireName: r'aliases')
  BuiltList<String>? get aliases;

  GenreNode._();

  factory GenreNode([void updates(GenreNodeBuilder b)]) = _$GenreNode;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GenreNodeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GenreNode> get serializer => _$GenreNodeSerializer();
}

class _$GenreNodeSerializer implements PrimitiveSerializer<GenreNode> {
  @override
  final Iterable<Type> types = const [GenreNode, _$GenreNode];

  @override
  final String wireName = r'GenreNode';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GenreNode object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.parent != null) {
      yield r'parent';
      yield serializers.serialize(
        object.parent,
        specifiedType: const FullType(String),
      );
    }
    if (object.aliases != null) {
      yield r'aliases';
      yield serializers.serialize(
        object.aliases,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GenreNode object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GenreNodeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'parent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.parent = valueDes;
          break;
        case r'aliases':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.aliases.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GenreNode deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GenreNodeBuilder();
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

