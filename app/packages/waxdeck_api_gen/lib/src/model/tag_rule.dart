//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'tag_rule.g.dart';

/// One tag predicate. With `value`, the rule matches items whose custom tag `key` equals it (case-insensitively); without, the rule matches items carrying `key` at all. 
///
/// Properties:
/// * [key] - Custom tag key, e.g. `ITUNESADVISORY`.
/// * [value] - Tag value to match; absent matches any value.
@BuiltValue()
abstract class TagRule implements Built<TagRule, TagRuleBuilder> {
  /// Custom tag key, e.g. `ITUNESADVISORY`.
  @BuiltValueField(wireName: r'key')
  String get key;

  /// Tag value to match; absent matches any value.
  @BuiltValueField(wireName: r'value')
  String? get value;

  TagRule._();

  factory TagRule([void updates(TagRuleBuilder b)]) = _$TagRule;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TagRuleBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TagRule> get serializer => _$TagRuleSerializer();
}

class _$TagRuleSerializer implements PrimitiveSerializer<TagRule> {
  @override
  final Iterable<Type> types = const [TagRule, _$TagRule];

  @override
  final String wireName = r'TagRule';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TagRule object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'key';
    yield serializers.serialize(
      object.key,
      specifiedType: const FullType(String),
    );
    if (object.value != null) {
      yield r'value';
      yield serializers.serialize(
        object.value,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    TagRule object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TagRuleBuilder result,
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
        case r'value':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.value = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TagRule deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TagRuleBuilder();
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

