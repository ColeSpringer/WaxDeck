//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'library_create.g.dart';

/// A new library root to register at runtime.
///
/// Properties:
/// * [name] - Display name, and the WaxFlow root name the same directory is served under for streaming. 
/// * [path] - Absolute filesystem path on the server. It must not overlap an existing root, the inbox folders, or the podcast download dir. 
/// * [media] - Content class the root holds. `mixed` (the default) admits both tracks and books. 
/// * [managed] - Whether the catalog may place and organize files under this root: uploads land here and the organizer may move files within it. The default keeps files strictly in place. 
@BuiltValue()
abstract class LibraryCreate implements Built<LibraryCreate, LibraryCreateBuilder> {
  /// Display name, and the WaxFlow root name the same directory is served under for streaming. 
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Absolute filesystem path on the server. It must not overlap an existing root, the inbox folders, or the podcast download dir. 
  @BuiltValueField(wireName: r'path')
  String get path;

  /// Content class the root holds. `mixed` (the default) admits both tracks and books. 
  @BuiltValueField(wireName: r'media')
  LibraryCreateMediaEnum? get media;
  // enum mediaEnum {  music,  audiobook,  mixed,  };

  /// Whether the catalog may place and organize files under this root: uploads land here and the organizer may move files within it. The default keeps files strictly in place. 
  @BuiltValueField(wireName: r'managed')
  bool? get managed;

  LibraryCreate._();

  factory LibraryCreate([void updates(LibraryCreateBuilder b)]) = _$LibraryCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LibraryCreateBuilder b) => b
      ..media = const LibraryCreateMediaEnum._('mixed')
      ..managed = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<LibraryCreate> get serializer => _$LibraryCreateSerializer();
}

class _$LibraryCreateSerializer implements PrimitiveSerializer<LibraryCreate> {
  @override
  final Iterable<Type> types = const [LibraryCreate, _$LibraryCreate];

  @override
  final String wireName = r'LibraryCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LibraryCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
    if (object.media != null) {
      yield r'media';
      yield serializers.serialize(
        object.media,
        specifiedType: const FullType(LibraryCreateMediaEnum),
      );
    }
    if (object.managed != null) {
      yield r'managed';
      yield serializers.serialize(
        object.managed,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LibraryCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LibraryCreateBuilder result,
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
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.path = valueDes;
          break;
        case r'media':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LibraryCreateMediaEnum),
          ) as LibraryCreateMediaEnum;
          result.media = valueDes;
          break;
        case r'managed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.managed = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LibraryCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LibraryCreateBuilder();
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

class LibraryCreateMediaEnum extends EnumClass {

  /// Content class the root holds. `mixed` (the default) admits both tracks and books. 
  @BuiltValueEnumConst(wireName: r'music')
  static const LibraryCreateMediaEnum music = _$libraryCreateMediaEnum_music;
  /// Content class the root holds. `mixed` (the default) admits both tracks and books. 
  @BuiltValueEnumConst(wireName: r'audiobook')
  static const LibraryCreateMediaEnum audiobook = _$libraryCreateMediaEnum_audiobook;
  /// Content class the root holds. `mixed` (the default) admits both tracks and books. 
  @BuiltValueEnumConst(wireName: r'mixed')
  static const LibraryCreateMediaEnum mixed = _$libraryCreateMediaEnum_mixed;

  static Serializer<LibraryCreateMediaEnum> get serializer => _$libraryCreateMediaEnumSerializer;

  const LibraryCreateMediaEnum._(String name): super(name);

  static BuiltSet<LibraryCreateMediaEnum> get values => _$libraryCreateMediaEnumValues;
  static LibraryCreateMediaEnum valueOf(String name) => _$libraryCreateMediaEnumValueOf(name);
}

