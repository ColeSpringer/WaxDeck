//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/genre_node.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'genre_tree.g.dart';

/// The canonical genre vocabulary in force.
///
/// Properties:
/// * [source_] - `default` while the instance runs on the tree WaxDeck ships, `custom` once one has been stored here. 
/// * [genres] - The vocabulary in display order: each top-level genre followed by the genres grouped under it, alphabetically throughout. 
@BuiltValue()
abstract class GenreTree implements Built<GenreTree, GenreTreeBuilder> {
  /// `default` while the instance runs on the tree WaxDeck ships, `custom` once one has been stored here. 
  @BuiltValueField(wireName: r'source')
  GenreTreeSource_Enum get source_;
  // enum source_Enum {  default,  custom,  };

  /// The vocabulary in display order: each top-level genre followed by the genres grouped under it, alphabetically throughout. 
  @BuiltValueField(wireName: r'genres')
  BuiltList<GenreNode> get genres;

  GenreTree._();

  factory GenreTree([void updates(GenreTreeBuilder b)]) = _$GenreTree;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GenreTreeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GenreTree> get serializer => _$GenreTreeSerializer();
}

class _$GenreTreeSerializer implements PrimitiveSerializer<GenreTree> {
  @override
  final Iterable<Type> types = const [GenreTree, _$GenreTree];

  @override
  final String wireName = r'GenreTree';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GenreTree object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(GenreTreeSource_Enum),
    );
    yield r'genres';
    yield serializers.serialize(
      object.genres,
      specifiedType: const FullType(BuiltList, [FullType(GenreNode)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GenreTree object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GenreTreeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(GenreTreeSource_Enum),
          ) as GenreTreeSource_Enum;
          result.source_ = valueDes;
          break;
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
  GenreTree deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GenreTreeBuilder();
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

class GenreTreeSource_Enum extends EnumClass {

  /// `default` while the instance runs on the tree WaxDeck ships, `custom` once one has been stored here. 
  @BuiltValueEnumConst(wireName: r'default')
  static const GenreTreeSource_Enum default_ = _$genreTreeSourceEnum_default_;
  /// `default` while the instance runs on the tree WaxDeck ships, `custom` once one has been stored here. 
  @BuiltValueEnumConst(wireName: r'custom')
  static const GenreTreeSource_Enum custom = _$genreTreeSourceEnum_custom;

  static Serializer<GenreTreeSource_Enum> get serializer => _$genreTreeSourceEnumSerializer;

  const GenreTreeSource_Enum._(String name): super(name);

  static BuiltSet<GenreTreeSource_Enum> get values => _$genreTreeSourceEnumValues;
  static GenreTreeSource_Enum valueOf(String name) => _$genreTreeSourceEnumValueOf(name);
}

