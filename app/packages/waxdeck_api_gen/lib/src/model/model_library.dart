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
/// * [path] - Absolute filesystem path of the root, for the administrative surface that manages it. Absent where the catalog cannot render the stored path as text (roots on non-UTF8 filesystems are stored as raw bytes). 
/// * [itemCount] - Playable items the catalog holds under this root. Present only where the caller asked for counts, and counted at read time, so it lags a running scan. 
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

  /// Absolute filesystem path of the root, for the administrative surface that manages it. Absent where the catalog cannot render the stored path as text (roots on non-UTF8 filesystems are stored as raw bytes). 
  @BuiltValueField(wireName: r'path')
  String? get path;

  /// Playable items the catalog holds under this root. Present only where the caller asked for counts, and counted at read time, so it lags a running scan. 
  @BuiltValueField(wireName: r'itemCount')
  int? get itemCount;

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
            specifiedType: const FullType(String),
          ) as String;
          result.media = valueDes;
          break;
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.path = valueDes;
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

