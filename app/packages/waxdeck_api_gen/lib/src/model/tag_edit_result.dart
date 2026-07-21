//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'tag_edit_result.g.dart';

/// The outcome of a tag edit.
///
/// Properties:
/// * [key] - The canonical uppercase key actually used.
/// * [stored] - Values stored after deduplication.
@BuiltValue()
abstract class TagEditResult implements Built<TagEditResult, TagEditResultBuilder> {
  /// The canonical uppercase key actually used.
  @BuiltValueField(wireName: r'key')
  String get key;

  /// Values stored after deduplication.
  @BuiltValueField(wireName: r'stored')
  int get stored;

  TagEditResult._();

  factory TagEditResult([void updates(TagEditResultBuilder b)]) = _$TagEditResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TagEditResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TagEditResult> get serializer => _$TagEditResultSerializer();
}

class _$TagEditResultSerializer implements PrimitiveSerializer<TagEditResult> {
  @override
  final Iterable<Type> types = const [TagEditResult, _$TagEditResult];

  @override
  final String wireName = r'TagEditResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TagEditResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'key';
    yield serializers.serialize(
      object.key,
      specifiedType: const FullType(String),
    );
    yield r'stored';
    yield serializers.serialize(
      object.stored,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TagEditResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TagEditResultBuilder result,
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
        case r'stored':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.stored = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TagEditResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TagEditResultBuilder();
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

