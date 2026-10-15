//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/item_file.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item_files.g.dart';

/// The files behind one item.
///
/// Properties:
/// * [files] - The primary, or a book's parts in reading order, then the copies. 
@BuiltValue()
abstract class ItemFiles implements Built<ItemFiles, ItemFilesBuilder> {
  /// The primary, or a book's parts in reading order, then the copies. 
  @BuiltValueField(wireName: r'files')
  BuiltList<ItemFile> get files;

  ItemFiles._();

  factory ItemFiles([void updates(ItemFilesBuilder b)]) = _$ItemFiles;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ItemFilesBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ItemFiles> get serializer => _$ItemFilesSerializer();
}

class _$ItemFilesSerializer implements PrimitiveSerializer<ItemFiles> {
  @override
  final Iterable<Type> types = const [ItemFiles, _$ItemFiles];

  @override
  final String wireName = r'ItemFiles';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ItemFiles object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'files';
    yield serializers.serialize(
      object.files,
      specifiedType: const FullType(BuiltList, [FullType(ItemFile)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ItemFiles object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ItemFilesBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'files':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ItemFile)]),
          ) as BuiltList<ItemFile>;
          result.files.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ItemFiles deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ItemFilesBuilder();
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


