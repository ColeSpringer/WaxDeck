//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'library_media.g.dart';

/// What a library holds.
///
/// Properties:
/// * [media] - The content class, as `LibraryCreate.media`.
@BuiltValue()
abstract class LibraryMedia implements Built<LibraryMedia, LibraryMediaBuilder> {
  /// The content class, as `LibraryCreate.media`.
  @BuiltValueField(wireName: r'media')
  LibraryMediaMediaEnum get media;
  // enum mediaEnum {  music,  audiobook,  mixed,  };

  LibraryMedia._();

  factory LibraryMedia([void updates(LibraryMediaBuilder b)]) = _$LibraryMedia;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LibraryMediaBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LibraryMedia> get serializer => _$LibraryMediaSerializer();
}

class _$LibraryMediaSerializer implements PrimitiveSerializer<LibraryMedia> {
  @override
  final Iterable<Type> types = const [LibraryMedia, _$LibraryMedia];

  @override
  final String wireName = r'LibraryMedia';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LibraryMedia object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'media';
    yield serializers.serialize(
      object.media,
      specifiedType: const FullType(LibraryMediaMediaEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LibraryMedia object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LibraryMediaBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'media':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LibraryMediaMediaEnum),
          ) as LibraryMediaMediaEnum;
          result.media = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LibraryMedia deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LibraryMediaBuilder();
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


/// The content class, as `LibraryCreate.media`.
class LibraryMediaMediaEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'music')
  static const LibraryMediaMediaEnum music = _$libraryMediaMediaEnum_music;
  @BuiltValueEnumConst(wireName: r'audiobook')
  static const LibraryMediaMediaEnum audiobook = _$libraryMediaMediaEnum_audiobook;
  @BuiltValueEnumConst(wireName: r'mixed')
  static const LibraryMediaMediaEnum mixed = _$libraryMediaMediaEnum_mixed;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const LibraryMediaMediaEnum unknownDefaultOpenApi = _$libraryMediaMediaEnum_unknownDefaultOpenApi;

  static Serializer<LibraryMediaMediaEnum> get serializer => _$libraryMediaMediaEnumSerializer;

  const LibraryMediaMediaEnum._(String name): super(name);

  static BuiltSet<LibraryMediaMediaEnum> get values => _$libraryMediaMediaEnumValues;
  static LibraryMediaMediaEnum valueOf(String name) => _$libraryMediaMediaEnumValueOf(name);
}

