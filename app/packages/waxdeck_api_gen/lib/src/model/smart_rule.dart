//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/rule_node.dart';
import 'package:waxdeck_api_gen/src/model/rule_sort.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'smart_rule.g.dart';

/// A smart playlist rule: a condition tree, optional sort order, and an optional row limit. Rules are evaluated per user on read; fields that read user state (stars, ratings, play counts) bind to the evaluating user at that moment. Without `sorts` the engine orders by title ascending so results are deterministic. Rules are bounded on write: at most 200 nodes total and at most 10 levels of nesting; larger rules answer `invalid-request`. 
///
/// Properties:
/// * [root] 
/// * [sorts] - Sort order, applied in sequence.
/// * [limit] - Maximum members, applied after sorting. Zero or absent means unlimited. 
@BuiltValue()
abstract class SmartRule implements Built<SmartRule, SmartRuleBuilder> {
  @BuiltValueField(wireName: r'root')
  RuleNode get root;

  /// Sort order, applied in sequence.
  @BuiltValueField(wireName: r'sorts')
  BuiltList<RuleSort>? get sorts;

  /// Maximum members, applied after sorting. Zero or absent means unlimited. 
  @BuiltValueField(wireName: r'limit')
  int? get limit;

  SmartRule._();

  factory SmartRule([void updates(SmartRuleBuilder b)]) = _$SmartRule;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SmartRuleBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SmartRule> get serializer => _$SmartRuleSerializer();
}

class _$SmartRuleSerializer implements PrimitiveSerializer<SmartRule> {
  @override
  final Iterable<Type> types = const [SmartRule, _$SmartRule];

  @override
  final String wireName = r'SmartRule';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SmartRule object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'root';
    yield serializers.serialize(
      object.root,
      specifiedType: const FullType(RuleNode),
    );
    if (object.sorts != null) {
      yield r'sorts';
      yield serializers.serialize(
        object.sorts,
        specifiedType: const FullType(BuiltList, [FullType(RuleSort)]),
      );
    }
    if (object.limit != null) {
      yield r'limit';
      yield serializers.serialize(
        object.limit,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SmartRule object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SmartRuleBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'root':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RuleNode),
          ) as RuleNode;
          result.root.replace(valueDes);
          break;
        case r'sorts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RuleSort)]),
          ) as BuiltList<RuleSort>;
          result.sorts.replace(valueDes);
          break;
        case r'limit':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.limit = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SmartRule deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SmartRuleBuilder();
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

