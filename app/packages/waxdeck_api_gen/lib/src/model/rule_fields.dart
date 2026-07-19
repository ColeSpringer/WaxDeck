//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/rule_field.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/rule_tag_key.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rule_fields.g.dart';

/// The rule field vocabulary for smart rule editors. `tag.KEY` fields are uniform and therefore not repeated per key: they are text-kind, accept `is`, `isNot`, `contains`, `startsWith`, `endsWith`, `isPresent`, and `isMissing` (never the ordered operators), and can never sort. On a tag field `isNot` matches items that do not carry that value, including items without the tag at all: the deny-list reading. 
///
/// Properties:
/// * [fields] - Every rule field.
/// * [tagKeys] - Custom tag keys, most used first.
@BuiltValue()
abstract class RuleFields implements Built<RuleFields, RuleFieldsBuilder> {
  /// Every rule field.
  @BuiltValueField(wireName: r'fields')
  BuiltList<RuleField> get fields;

  /// Custom tag keys, most used first.
  @BuiltValueField(wireName: r'tagKeys')
  BuiltList<RuleTagKey> get tagKeys;

  RuleFields._();

  factory RuleFields([void updates(RuleFieldsBuilder b)]) = _$RuleFields;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RuleFieldsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RuleFields> get serializer => _$RuleFieldsSerializer();
}

class _$RuleFieldsSerializer implements PrimitiveSerializer<RuleFields> {
  @override
  final Iterable<Type> types = const [RuleFields, _$RuleFields];

  @override
  final String wireName = r'RuleFields';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RuleFields object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'fields';
    yield serializers.serialize(
      object.fields,
      specifiedType: const FullType(BuiltList, [FullType(RuleField)]),
    );
    yield r'tagKeys';
    yield serializers.serialize(
      object.tagKeys,
      specifiedType: const FullType(BuiltList, [FullType(RuleTagKey)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RuleFields object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RuleFieldsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'fields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RuleField)]),
          ) as BuiltList<RuleField>;
          result.fields.replace(valueDes);
          break;
        case r'tagKeys':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RuleTagKey)]),
          ) as BuiltList<RuleTagKey>;
          result.tagKeys.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RuleFields deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RuleFieldsBuilder();
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

