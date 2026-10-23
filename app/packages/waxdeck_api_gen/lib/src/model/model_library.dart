//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'model_library.g.dart';

/// One catalog library (a scanned root).
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
/// * [configured] - The server's configuration names the library (`WAXDECK_LIBRARY_ROOTS`), so every start registers it and removeLibrary refuses it until the configuration drops it. Absent means false. 
/// * [unreachable] - The library's folder was not there at its last scan, which marked nothing under it missing: its items stay listed and play once it is back. Absent means false. 
/// * [writable] - For a managed library, whether the server could write to its folder when last checked; when false, uploads, organize moves and deletes into it fail. The server checks when it starts, when the library is created or arrives from elsewhere (the waxbin CLI), when its read-only flag or the server's is lifted, every half hour, and after a write into a library's folder is refused; listing the libraries checks nothing. Absent on an in-place library and on one the server treats as read-only (its own flag or the whole server's), which are not checked. 
@BuiltValue(instantiable: false)
abstract class ModelLibrary  {
  /// Library PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Display name (the configured root name).
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Content class the library holds. Currently `music`, `audiobook`, `podcast`, or `mixed`; new values may appear. 
  @BuiltValueField(wireName: r'media')
  String? get media;

  /// The server's configuration names what the library holds (`WAXDECK_AUDIOBOOK_ROOTS`), so setLibraryMedia refuses any other media until the configuration changes. Absent means false. 
  @BuiltValueField(wireName: r'mediaDeclared')
  bool? get mediaDeclared;

  /// Absolute filesystem path of the root, for the administrative surface that manages it. Absent where the catalog cannot render the stored path as text (roots on non-UTF8 filesystems are stored as raw bytes). 
  @BuiltValueField(wireName: r'path')
  String? get path;

  /// Playable items the catalog holds under this root. Present only where the caller asked for counts, and counted at read time, so it lags a running scan. 
  @BuiltValueField(wireName: r'itemCount')
  int? get itemCount;

  /// The catalog keeps the library's files as they are.
  @BuiltValueField(wireName: r'readOnly')
  bool get readOnly;

  /// A scan names an untagged file from its folders (setLibraryFolderFallback). In-place libraries only. 
  @BuiltValueField(wireName: r'folderFallback')
  bool? get folderFallback;

  /// The catalog may place and move files in the library.
  @BuiltValueField(wireName: r'managed')
  bool get managed;

  /// The organize profile a managed library is laid out by.
  @BuiltValueField(wireName: r'profile')
  String? get profile;

  /// The server's configuration names the library (`WAXDECK_LIBRARY_ROOTS`), so every start registers it and removeLibrary refuses it until the configuration drops it. Absent means false. 
  @BuiltValueField(wireName: r'configured')
  bool? get configured;

  /// The library's folder was not there at its last scan, which marked nothing under it missing: its items stay listed and play once it is back. Absent means false. 
  @BuiltValueField(wireName: r'unreachable')
  bool? get unreachable;

  /// For a managed library, whether the server could write to its folder when last checked; when false, uploads, organize moves and deletes into it fail. The server checks when it starts, when the library is created or arrives from elsewhere (the waxbin CLI), when its read-only flag or the server's is lifted, every half hour, and after a write into a library's folder is refused; listing the libraries checks nothing. Absent on an in-place library and on one the server treats as read-only (its own flag or the whole server's), which are not checked. 
  @BuiltValueField(wireName: r'writable')
  bool? get writable;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModelLibrary> get serializer => _$ModelLibrarySerializer();
}

class _$ModelLibrarySerializer implements PrimitiveSerializer<ModelLibrary> {
  @override
  final Iterable<Type> types = const [ModelLibrary];

  @override
  final String wireName = r'ModelLibrary';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModelLibrary object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.media != null) {
      yield r'media';
      yield serializers.serialize(
        object.media,
        specifiedType: const FullType(String),
      );
    }
    if (object.mediaDeclared != null) {
      yield r'mediaDeclared';
      yield serializers.serialize(
        object.mediaDeclared,
        specifiedType: const FullType(bool),
      );
    }
    if (object.path != null) {
      yield r'path';
      yield serializers.serialize(
        object.path,
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
    yield r'readOnly';
    yield serializers.serialize(
      object.readOnly,
      specifiedType: const FullType(bool),
    );
    if (object.folderFallback != null) {
      yield r'folderFallback';
      yield serializers.serialize(
        object.folderFallback,
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
    if (object.configured != null) {
      yield r'configured';
      yield serializers.serialize(
        object.configured,
        specifiedType: const FullType(bool),
      );
    }
    if (object.unreachable != null) {
      yield r'unreachable';
      yield serializers.serialize(
        object.unreachable,
        specifiedType: const FullType(bool),
      );
    }
    if (object.writable != null) {
      yield r'writable';
      yield serializers.serialize(
        object.writable,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ModelLibrary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  ModelLibrary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($ModelLibrary)) as $ModelLibrary;
  }
}


/// a concrete implementation of [ModelLibrary], since [ModelLibrary] is not instantiable
@BuiltValue(instantiable: true)
abstract class $ModelLibrary implements ModelLibrary, Built<$ModelLibrary, $ModelLibraryBuilder> {
  $ModelLibrary._();

  factory $ModelLibrary([void Function($ModelLibraryBuilder)? updates]) = _$$ModelLibrary;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($ModelLibraryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$ModelLibrary> get serializer => _$$ModelLibrarySerializer();
}

class _$$ModelLibrarySerializer implements PrimitiveSerializer<$ModelLibrary> {
  @override
  final Iterable<Type> types = const [$ModelLibrary, _$$ModelLibrary];

  @override
  final String wireName = r'$ModelLibrary';

  @override
  Object serialize(
    Serializers serializers,
    $ModelLibrary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(ModelLibrary))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModelLibraryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'media':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.media = valueDes;
          break;
        case r'mediaDeclared':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.mediaDeclared = valueDes;
          break;
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.path = valueDes;
          break;
        case r'itemCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.itemCount = valueDes;
          break;
        case r'readOnly':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.readOnly = valueDes;
          break;
        case r'folderFallback':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.folderFallback = valueDes;
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
        case r'configured':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.configured = valueDes;
          break;
        case r'unreachable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.unreachable = valueDes;
          break;
        case r'writable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.writable = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  $ModelLibrary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $ModelLibraryBuilder();
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

