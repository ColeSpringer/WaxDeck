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

/// A smart playlist rule: a condition tree, optional sort order, and an optional limit. Rules are evaluated per user on read; fields that read user state (stars, ratings, play counts) bind to the evaluating user at that moment. Without `sorts` the engine orders by title ascending so results are deterministic. Rules are bounded on write: at most 200 nodes total and at most 10 levels of nesting; larger rules answer `invalid-request`. 
///
/// Properties:
/// * [root] 
/// * [sorts] - Sort order, applied in sequence. Rejected with `limitMode` `random` (the shuffle is the order). 
/// * [limit] - The limit value, interpreted by `limitMode`: a maximum member count (`count`, the default), a maximum count of a random draw (`random`), or a playtime or size budget in whole minutes (`minutes`) or megabytes (`megabytes`). Zero or absent means unlimited and is only valid with `count`. 
/// * [limitMode] - How `limit` is interpreted: `count` (the default; a plain member cap in sort order), `random` (that many members drawn by a seeded shuffle, so a rule can mean \"25 songs at random\"), `minutes` (members accumulated in rule order until the next would exceed `limit` minutes of playtime), or `megabytes` (the same, budgeted by summed file size, so a rule can mean \"what fits on the device\"). A budget mode skips a member with no measurable playtime or size rather than counting it as free. A string, not a closed enum; unknown values answer `invalid-request`. Absent means `count`. 
/// * [limitSeed] - Pins the shuffle order of a `random` or budget evaluation so the same rule yields the same members each read; zero or absent draws a fresh order per read. Only meaningful when `limitMode` is not `count`; supplying it with `count` answers `invalid-request`. 
@BuiltValue()
abstract class SmartRule implements Built<SmartRule, SmartRuleBuilder> {
  @BuiltValueField(wireName: r'root')
  RuleNode get root;

  /// Sort order, applied in sequence. Rejected with `limitMode` `random` (the shuffle is the order). 
  @BuiltValueField(wireName: r'sorts')
  BuiltList<RuleSort>? get sorts;

  /// The limit value, interpreted by `limitMode`: a maximum member count (`count`, the default), a maximum count of a random draw (`random`), or a playtime or size budget in whole minutes (`minutes`) or megabytes (`megabytes`). Zero or absent means unlimited and is only valid with `count`. 
  @BuiltValueField(wireName: r'limit')
  int? get limit;

  /// How `limit` is interpreted: `count` (the default; a plain member cap in sort order), `random` (that many members drawn by a seeded shuffle, so a rule can mean \"25 songs at random\"), `minutes` (members accumulated in rule order until the next would exceed `limit` minutes of playtime), or `megabytes` (the same, budgeted by summed file size, so a rule can mean \"what fits on the device\"). A budget mode skips a member with no measurable playtime or size rather than counting it as free. A string, not a closed enum; unknown values answer `invalid-request`. Absent means `count`. 
  @BuiltValueField(wireName: r'limitMode')
  String? get limitMode;

  /// Pins the shuffle order of a `random` or budget evaluation so the same rule yields the same members each read; zero or absent draws a fresh order per read. Only meaningful when `limitMode` is not `count`; supplying it with `count` answers `invalid-request`. 
  @BuiltValueField(wireName: r'limitSeed')
  int? get limitSeed;

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
    if (object.limitMode != null) {
      yield r'limitMode';
      yield serializers.serialize(
        object.limitMode,
        specifiedType: const FullType(String),
      );
    }
    if (object.limitSeed != null) {
      yield r'limitSeed';
      yield serializers.serialize(
        object.limitSeed,
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
        case r'limitMode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.limitMode = valueDes;
          break;
        case r'limitSeed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.limitSeed = valueDes;
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

