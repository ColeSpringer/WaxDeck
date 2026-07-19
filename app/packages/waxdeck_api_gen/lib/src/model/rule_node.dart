//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rule_node.g.dart';

/// One node of a rule's condition tree. `type` selects the shape: `all` (every child must match) and `any` (at least one child must match) carry `nodes`; `not` inverts its single `node`; `condition` compares one `field` with `op` against `value` (or `values` for `inTheRange`, exactly two, low then high). An `all` with no children matches everything; an `any` with no children matches nothing. Unknown `type` strings are rejected on write. Condition values are strings on the wire regardless of the field's kind: numbers in decimal, booleans as `true` or `false`, dates as absolute RFC 3339 timestamps (there are no relative date operators; a rule meaning \"recently\" must be re-saved to move its cutoff), media types as `music`, `podcast`, or `audiobook`. `inTheRange` is inclusive on both ends. The field vocabulary and each field's accepted operators come from the rule-fields endpoint; custom tags are addressed as `tag.KEY`. 
///
/// Properties:
/// * [type] - `all`, `any`, `not`, or `condition`.
/// * [nodes] - Children of an `all` or `any` group.
/// * [node] 
/// * [field] - Field name from the rule-fields vocabulary.
/// * [op] - Operator: one of `is`, `isNot`, `contains`, `startsWith`, `endsWith`, `gt`, `lt`, `gte`, `lte`, `inTheRange`, `before`, `after`, `isPresent`, `isMissing`. Each field accepts a subset; see the rule-fields endpoint. 
/// * [value] - Comparison value, string-encoded per the field's kind.
/// * [values] - Exactly two values for `inTheRange`, low then high.
@BuiltValue()
abstract class RuleNode implements Built<RuleNode, RuleNodeBuilder> {
  /// `all`, `any`, `not`, or `condition`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// Children of an `all` or `any` group.
  @BuiltValueField(wireName: r'nodes')
  BuiltList<RuleNode>? get nodes;

  @BuiltValueField(wireName: r'node')
  RuleNode? get node;

  /// Field name from the rule-fields vocabulary.
  @BuiltValueField(wireName: r'field')
  String? get field;

  /// Operator: one of `is`, `isNot`, `contains`, `startsWith`, `endsWith`, `gt`, `lt`, `gte`, `lte`, `inTheRange`, `before`, `after`, `isPresent`, `isMissing`. Each field accepts a subset; see the rule-fields endpoint. 
  @BuiltValueField(wireName: r'op')
  String? get op;

  /// Comparison value, string-encoded per the field's kind.
  @BuiltValueField(wireName: r'value')
  String? get value;

  /// Exactly two values for `inTheRange`, low then high.
  @BuiltValueField(wireName: r'values')
  BuiltList<String>? get values;

  RuleNode._();

  factory RuleNode([void updates(RuleNodeBuilder b)]) = _$RuleNode;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RuleNodeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RuleNode> get serializer => _$RuleNodeSerializer();
}

class _$RuleNodeSerializer implements PrimitiveSerializer<RuleNode> {
  @override
  final Iterable<Type> types = const [RuleNode, _$RuleNode];

  @override
  final String wireName = r'RuleNode';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RuleNode object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    if (object.nodes != null) {
      yield r'nodes';
      yield serializers.serialize(
        object.nodes,
        specifiedType: const FullType(BuiltList, [FullType(RuleNode)]),
      );
    }
    if (object.node != null) {
      yield r'node';
      yield serializers.serialize(
        object.node,
        specifiedType: const FullType(RuleNode),
      );
    }
    if (object.field != null) {
      yield r'field';
      yield serializers.serialize(
        object.field,
        specifiedType: const FullType(String),
      );
    }
    if (object.op != null) {
      yield r'op';
      yield serializers.serialize(
        object.op,
        specifiedType: const FullType(String),
      );
    }
    if (object.value != null) {
      yield r'value';
      yield serializers.serialize(
        object.value,
        specifiedType: const FullType(String),
      );
    }
    if (object.values != null) {
      yield r'values';
      yield serializers.serialize(
        object.values,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RuleNode object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RuleNodeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.type = valueDes;
          break;
        case r'nodes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RuleNode)]),
          ) as BuiltList<RuleNode>;
          result.nodes.replace(valueDes);
          break;
        case r'node':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RuleNode),
          ) as RuleNode;
          result.node.replace(valueDes);
          break;
        case r'field':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.field = valueDes;
          break;
        case r'op':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.op = valueDes;
          break;
        case r'value':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.value = valueDes;
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
  RuleNode deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RuleNodeBuilder();
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

