//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/model_library.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'libraries.g.dart';

/// All catalog libraries.
///
/// Properties:
/// * [libraries] 
@BuiltValue()
abstract class Libraries implements Built<Libraries, LibrariesBuilder> {
  @BuiltValueField(wireName: r'libraries')
  BuiltList<ModelLibrary> get libraries;

  Libraries._();

  factory Libraries([void updates(LibrariesBuilder b)]) = _$Libraries;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LibrariesBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Libraries> get serializer => _$LibrariesSerializer();
}

class _$LibrariesSerializer implements PrimitiveSerializer<Libraries> {
  @override
  final Iterable<Type> types = const [Libraries, _$Libraries];

  @override
  final String wireName = r'Libraries';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Libraries object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'libraries';
    yield serializers.serialize(
      object.libraries,
      specifiedType: const FullType(BuiltList, [FullType(ModelLibrary)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Libraries object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LibrariesBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'libraries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ModelLibrary)]),
          ) as BuiltList<ModelLibrary>;
          result.libraries.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Libraries deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LibrariesBuilder();
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

