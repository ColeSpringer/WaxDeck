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
/// * [streamingWarning] - Present when the library exists but streaming from it does not work yet, saying what an administrator still has to do. Creating a root reconciles the WaxFlow sidecar so it serves the same directory; where that cannot happen (a sidecar too old to reload, a path it cannot open) browsing, downloading, and direct playback still work and streaming waits for a sidecar restart. Absent means streaming works now. 
@BuiltValue()
abstract class LibraryCreated implements ModelLibrary, Built<LibraryCreated, LibraryCreatedBuilder> {
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
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.path != null) {
      yield r'path';
      yield serializers.serialize(
        object.path,
        specifiedType: const FullType(String),
      );
    }
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
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
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'media':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.media = valueDes;
          break;
        case r'streamingWarning':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.streamingWarning = valueDes;
          break;
        case r'itemCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
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

