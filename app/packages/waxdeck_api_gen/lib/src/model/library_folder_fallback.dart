//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'library_folder_fallback.g.dart';

/// Whether a library names untagged files from their folders.
///
/// Properties:
/// * [folderFallback] - Whether a scan names an untagged file from its folders.
/// * [libraryPid] - The library (response only).
@BuiltValue()
abstract class LibraryFolderFallback implements Built<LibraryFolderFallback, LibraryFolderFallbackBuilder> {
  /// Whether a scan names an untagged file from its folders.
  @BuiltValueField(wireName: r'folderFallback')
  bool get folderFallback;

  /// The library (response only).
  @BuiltValueField(wireName: r'libraryPid')
  String? get libraryPid;

  LibraryFolderFallback._();

  factory LibraryFolderFallback([void updates(LibraryFolderFallbackBuilder b)]) = _$LibraryFolderFallback;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LibraryFolderFallbackBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LibraryFolderFallback> get serializer => _$LibraryFolderFallbackSerializer();
}

class _$LibraryFolderFallbackSerializer implements PrimitiveSerializer<LibraryFolderFallback> {
  @override
  final Iterable<Type> types = const [LibraryFolderFallback, _$LibraryFolderFallback];

  @override
  final String wireName = r'LibraryFolderFallback';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LibraryFolderFallback object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'folderFallback';
    yield serializers.serialize(
      object.folderFallback,
      specifiedType: const FullType(bool),
    );
    if (object.libraryPid != null) {
      yield r'libraryPid';
      yield serializers.serialize(
        object.libraryPid,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LibraryFolderFallback object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LibraryFolderFallbackBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'folderFallback':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.folderFallback = valueDes;
          break;
        case r'libraryPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.libraryPid = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LibraryFolderFallback deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LibraryFolderFallbackBuilder();
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


