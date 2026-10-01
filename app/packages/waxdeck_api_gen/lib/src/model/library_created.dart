//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/model_library.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'library_created.g.dart';

/// A newly created library, with any degradation it left behind.
///
/// Properties:
/// * [pid] - Library PID.
/// * [name] - Display name (the configured root name).
/// * [media] - Content class the library holds. Currently `music`, `audiobook`, `podcast`, or `mixed`; new values may appear. 
/// * [path] - Absolute filesystem path of the root, for the administrative surface that manages it. Absent where the catalog cannot render the stored path as text (roots on non-UTF8 filesystems are stored as raw bytes). 
/// * [itemCount] - Playable items the catalog holds under this root. Present only where the caller asked for counts, and counted at read time, so it lags a running scan. 
/// * [readOnly] - The catalog keeps the library's files as they are.
/// * [managed] - The catalog may place and move files in the library.
/// * [profile] - The organize profile a managed library is laid out by.
/// * [streamingWarning] - Present when the library exists but streaming from it does not work yet, saying what an administrator still has to do. Creating a root reconciles the WaxFlow sidecar so it serves the same directory; where that cannot happen (a sidecar too old to reload, a path it cannot open) browsing, downloading, and direct playback still work and streaming waits for a sidecar restart. Absent means streaming works now. 
/// * [scanStarted] - Whether creating the library started a scan of every root. False when another catalog job was already running: that job began before this root existed, so the root is indexed by the next scan, which an administrator can start from the rescan endpoint once the running job ends. 
@BuiltValue()
abstract class LibraryCreated implements ModelLibrary, Built<LibraryCreated, LibraryCreatedBuilder> {
  /// Whether creating the library started a scan of every root. False when another catalog job was already running: that job began before this root existed, so the root is indexed by the next scan, which an administrator can start from the rescan endpoint once the running job ends. 
  @BuiltValueField(wireName: r'scanStarted')
  bool? get scanStarted;

  /// Present when the library exists but streaming from it does not work yet, saying what an administrator still has to do. Creating a root reconciles the WaxFlow sidecar so it serves the same directory; where that cannot happen (a sidecar too old to reload, a path it cannot open) browsing, downloading, and direct playback still work and streaming waits for a sidecar restart. Absent means streaming works now. 
  @BuiltValueField(wireName: r'streamingWarning')
  String? get streamingWarning;

  LibraryCreated._();

  factory LibraryCreated([void updates(LibraryCreatedBuilder b)]) = _$LibraryCreated;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LibraryCreatedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LibraryCreated> get serializer => _$LibraryCreatedSerializer();
}

class _$LibraryCreatedSerializer implements PrimitiveSerializer<LibraryCreated> {
  @override
  final Iterable<Type> types = const [LibraryCreated, _$LibraryCreated];

  @override
  final String wireName = r'LibraryCreated';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LibraryCreated object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.path != null) {
      yield r'path';
      yield serializers.serialize(
        object.path,
        specifiedType: const FullType(String),
      );
    }
    if (object.scanStarted != null) {
      yield r'scanStarted';
      yield serializers.serialize(
        object.scanStarted,
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
    if (object.streamingWarning != null) {
      yield r'streamingWarning';
      yield serializers.serialize(
        object.streamingWarning,
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
    LibraryCreated object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LibraryCreatedBuilder result,
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
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.scanStarted = valueDes;
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
        case r'streamingWarning':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.streamingWarning = valueDes;
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
  LibraryCreated deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LibraryCreatedBuilder();
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


