//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'library_matching.g.dart';

/// A library's automatic matching behavior.
///
/// Properties:
/// * [mode] - The matching mode.
@BuiltValue()
abstract class LibraryMatching implements Built<LibraryMatching, LibraryMatchingBuilder> {
  /// The matching mode.
  @BuiltValueField(wireName: r'mode')
  LibraryMatchingModeEnum get mode;
  // enum modeEnum {  auto,  review,  off,  };

  LibraryMatching._();

  factory LibraryMatching([void updates(LibraryMatchingBuilder b)]) = _$LibraryMatching;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LibraryMatchingBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LibraryMatching> get serializer => _$LibraryMatchingSerializer();
}

class _$LibraryMatchingSerializer implements PrimitiveSerializer<LibraryMatching> {
  @override
  final Iterable<Type> types = const [LibraryMatching, _$LibraryMatching];

  @override
  final String wireName = r'LibraryMatching';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LibraryMatching object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'mode';
    yield serializers.serialize(
      object.mode,
      specifiedType: const FullType(LibraryMatchingModeEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LibraryMatching object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LibraryMatchingBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LibraryMatchingModeEnum),
          ) as LibraryMatchingModeEnum;
          result.mode = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LibraryMatching deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LibraryMatchingBuilder();
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

class LibraryMatchingModeEnum extends EnumClass {

  /// The matching mode.
  @BuiltValueEnumConst(wireName: r'auto')
  static const LibraryMatchingModeEnum auto = _$libraryMatchingModeEnum_auto;
  /// The matching mode.
  @BuiltValueEnumConst(wireName: r'review')
  static const LibraryMatchingModeEnum review = _$libraryMatchingModeEnum_review;
  /// The matching mode.
  @BuiltValueEnumConst(wireName: r'off')
  static const LibraryMatchingModeEnum off = _$libraryMatchingModeEnum_off;
  /// The matching mode.
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const LibraryMatchingModeEnum unknownDefaultOpenApi = _$libraryMatchingModeEnum_unknownDefaultOpenApi;

  static Serializer<LibraryMatchingModeEnum> get serializer => _$libraryMatchingModeEnumSerializer;

  const LibraryMatchingModeEnum._(String name): super(name);

  static BuiltSet<LibraryMatchingModeEnum> get values => _$libraryMatchingModeEnumValues;
  static LibraryMatchingModeEnum valueOf(String name) => _$libraryMatchingModeEnumValueOf(name);
}

