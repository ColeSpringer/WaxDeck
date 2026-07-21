//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_rule_count.g.dart';

/// One rule's current standing.
///
/// Properties:
/// * [rule] - The rule name.
/// * [label] - Human-readable rule label.
/// * [failing] - Items currently failing the rule.
/// * [fixable] - Whether the bulk-fix endpoint automates this rule.
@BuiltValue()
abstract class HealthRuleCount implements Built<HealthRuleCount, HealthRuleCountBuilder> {
  /// The rule name.
  @BuiltValueField(wireName: r'rule')
  String get rule;

  /// Human-readable rule label.
  @BuiltValueField(wireName: r'label')
  String? get label;

  /// Items currently failing the rule.
  @BuiltValueField(wireName: r'failing')
  int get failing;

  /// Whether the bulk-fix endpoint automates this rule.
  @BuiltValueField(wireName: r'fixable')
  bool get fixable;

  HealthRuleCount._();

  factory HealthRuleCount([void updates(HealthRuleCountBuilder b)]) = _$HealthRuleCount;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthRuleCountBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthRuleCount> get serializer => _$HealthRuleCountSerializer();
}

class _$HealthRuleCountSerializer implements PrimitiveSerializer<HealthRuleCount> {
  @override
  final Iterable<Type> types = const [HealthRuleCount, _$HealthRuleCount];

  @override
  final String wireName = r'HealthRuleCount';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthRuleCount object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'rule';
    yield serializers.serialize(
      object.rule,
      specifiedType: const FullType(String),
    );
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType(String),
      );
    }
    yield r'failing';
    yield serializers.serialize(
      object.failing,
      specifiedType: const FullType(int),
    );
    yield r'fixable';
    yield serializers.serialize(
      object.fixable,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    HealthRuleCount object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HealthRuleCountBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'rule':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.rule = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.label = valueDes;
          break;
        case r'failing':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.failing = valueDes;
          break;
        case r'fixable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.fixable = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HealthRuleCount deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthRuleCountBuilder();
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

