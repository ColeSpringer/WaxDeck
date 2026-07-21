//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'custom_tag.g.dart';

/// One custom tag.
///
/// Properties:
/// * [key] - Canonical uppercase key.
/// * [values] - Ordered values.
@BuiltValue()
abstract class CustomTag implements Built<CustomTag, CustomTagBuilder> {
  /// Canonical uppercase key.
  @BuiltValueField(wireName: r'key')
  String get key;

  /// Ordered values.
  @BuiltValueField(wireName: r'values')
  BuiltList<String> get values;

  CustomTag._();

  factory CustomTag([void updates(CustomTagBuilder b)]) = _$CustomTag;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CustomTagBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CustomTag> get serializer => _$CustomTagSerializer();
}

class _$CustomTagSerializer implements PrimitiveSerializer<CustomTag> {
  @override
  final Iterable<Type> types = const [CustomTag, _$CustomTag];

  @override
  final String wireName = r'CustomTag';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CustomTag object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'key';
    yield serializers.serialize(
      object.key,
      specifiedType: const FullType(String),
    );
    yield r'values';
    yield serializers.serialize(
      object.values,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CustomTag object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CustomTagBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.key = valueDes;
          break;
        case r'values':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.values.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CustomTag deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CustomTagBuilder();
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

