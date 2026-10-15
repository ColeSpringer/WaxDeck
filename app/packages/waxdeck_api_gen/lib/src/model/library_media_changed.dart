//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/model_library.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'library_media_changed.g.dart';

/// A library whose content class changed.
///
/// Properties:
/// * [pid] - Library PID.
/// * [name] - Display name (the configured root name).
/// * [media] - Content class the library holds. Currently `music`, `audiobook`, `podcast`, or `mixed`; new values may appear. 
/// * [mediaDeclared] - The server's configuration names what the library holds (`WAXDECK_AUDIOBOOK_ROOTS`), so setLibraryMedia refuses any other media until the configuration changes. Absent means false. 
/// * [path] - Absolute filesystem path of the root, for the administrative surface that manages it. Absent where the catalog cannot render the stored path as text (roots on non-UTF8 filesystems are stored as raw bytes). 
/// * [itemCount] - Playable items the catalog holds under this root. Present only where the caller asked for counts, and counted at read time, so it lags a running scan. 
/// * [readOnly] - The catalog keeps the library's files as they are.
/// * [folderFallback] - A scan names an untagged file from its folders (setLibraryFolderFallback). In-place libraries only. 
/// * [managed] - The catalog may place and move files in the library.
/// * [profile] - The organize profile a managed library is laid out by.
/// * [scanStarted] - Whether the scan that applies the change started. False when the library already held that media, so there was nothing to apply, and when another catalog job was already running: a change onto `audiobook` is then applied by the next scan, and any other by the next rescan that re-reads every file (`force`), which an administrator starts once the running job ends. 
@BuiltValue()
abstract class LibraryMediaChanged implements ModelLibrary, Built<LibraryMediaChanged, LibraryMediaChangedBuilder> {
  /// Whether the scan that applies the change started. False when the library already held that media, so there was nothing to apply, and when another catalog job was already running: a change onto `audiobook` is then applied by the next scan, and any other by the next rescan that re-reads every file (`force`), which an administrator starts once the running job ends. 
  @BuiltValueField(wireName: r'scanStarted')
  bool get scanStarted;

  LibraryMediaChanged._();

  factory LibraryMediaChanged([void updates(LibraryMediaChangedBuilder b)]) = _$LibraryMediaChanged;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LibraryMediaChangedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LibraryMediaChanged> get serializer => _$LibraryMediaChangedSerializer();
}

class _$LibraryMediaChangedSerializer implements PrimitiveSerializer<LibraryMediaChanged> {
  @override
  final Iterable<Type> types = const [LibraryMediaChanged, _$LibraryMediaChanged];

  @override
  final String wireName = r'LibraryMediaChanged';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LibraryMediaChanged object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.path != null) {
      yield r'path';
      yield serializers.serialize(
        object.path,
        specifiedType: const FullType(String),
      );
    }
    yield r'scanStarted';
    yield serializers.serialize(
      object.scanStarted,
      specifiedType: const FullType(bool),
    );
    if (object.folderFallback != null) {
      yield r'folderFallback';
      yield serializers.serialize(
        object.folderFallback,
        specifiedType: const FullType(bool),
      );
    }
    if (object.mediaDeclared != null) {
      yield r'mediaDeclared';
      yield serializers.serialize(
        object.mediaDeclared,
        specifiedType: const FullType(bool),
      );
    }
    yield r'managed';
    yield serializers.serialize(
      object.managed,
      specifiedType: const FullType(bool),
    );
    if (object.profile != null) {
      yield r'profile';
      yield serializers.serialize(
        object.profile,
        specifiedType: const FullType(String),
      );
    }
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'readOnly';
    yield serializers.serialize(
      object.readOnly,
      specifiedType: const FullType(bool),
    );
    if (object.media != null) {
      yield r'media';
      yield serializers.serialize(
        object.media,
        specifiedType: const FullType(String),
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
    LibraryMediaChanged object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LibraryMediaChangedBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.path = valueDes;
          break;
        case r'scanStarted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.scanStarted = valueDes;
          break;
        case r'folderFallback':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.folderFallback = valueDes;
          break;
        case r'mediaDeclared':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.mediaDeclared = valueDes;
          break;
        case r'managed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.managed = valueDes;
          break;
        case r'profile':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.profile = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'readOnly':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.readOnly = valueDes;
          break;
        case r'media':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.media = valueDes;
          break;
        case r'itemCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
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
  LibraryMediaChanged deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LibraryMediaChangedBuilder();
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


