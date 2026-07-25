//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/genre_node.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'genre_tree_update.g.dart';

/// A replacement genre vocabulary.
///
/// Properties:
/// * [genres] - The whole vocabulary. An empty list clears the override and returns the instance to the shipped default. 
@BuiltValue()
abstract class GenreTreeUpdate implements Built<GenreTreeUpdate, GenreTreeUpdateBuilder> {
  /// The whole vocabulary. An empty list clears the override and returns the instance to the shipped default. 
  @BuiltValueField(wireName: r'genres')
  BuiltList<GenreNode> get genres;

  GenreTreeUpdate._();

  factory GenreTreeUpdate([void updates(GenreTreeUpdateBuilder b)]) = _$GenreTreeUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GenreTreeUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GenreTreeUpdate> get serializer => _$GenreTreeUpdateSerializer();
}

class _$GenreTreeUpdateSerializer implements PrimitiveSerializer<GenreTreeUpdate> {
  @override
  final Iterable<Type> types = const [GenreTreeUpdate, _$GenreTreeUpdate];

  @override
  final String wireName = r'GenreTreeUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GenreTreeUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'genres';
    yield serializers.serialize(
      object.genres,
      specifiedType: const FullType(BuiltList, [FullType(GenreNode)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GenreTreeUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GenreTreeUpdateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'genres':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(GenreNode)]),
          ) as BuiltList<GenreNode>;
          result.genres.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GenreTreeUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GenreTreeUpdateBuilder();
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

