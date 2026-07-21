//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'tag_edit.g.dart';

/// Replacement values for one custom tag.
///
/// Properties:
/// * [values] - Ordered values; empty clears the tag.
/// * [lock] - Lock `tag.KEY`.
/// * [force] - Override an existing lock.
@BuiltValue()
abstract class TagEdit implements Built<TagEdit, TagEditBuilder> {
  /// Ordered values; empty clears the tag.
  @BuiltValueField(wireName: r'values')
  BuiltList<String> get values;

  /// Lock `tag.KEY`.
  @BuiltValueField(wireName: r'lock')
  bool? get lock;

  /// Override an existing lock.
  @BuiltValueField(wireName: r'force')
  bool? get force;

  TagEdit._();

  factory TagEdit([void updates(TagEditBuilder b)]) = _$TagEdit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TagEditBuilder b) => b
      ..lock = true
      ..force = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<TagEdit> get serializer => _$TagEditSerializer();
}

class _$TagEditSerializer implements PrimitiveSerializer<TagEdit> {
  @override
  final Iterable<Type> types = const [TagEdit, _$TagEdit];

  @override
  final String wireName = r'TagEdit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TagEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'values';
    yield serializers.serialize(
      object.values,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.lock != null) {
      yield r'lock';
      yield serializers.serialize(
        object.lock,
        specifiedType: const FullType(bool),
      );
    }
    if (object.force != null) {
      yield r'force';
      yield serializers.serialize(
        object.force,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    TagEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TagEditBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'values':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.values.replace(valueDes);
          break;
        case r'lock':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.lock = valueDes;
          break;
        case r'force':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.force = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TagEdit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TagEditBuilder();
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

