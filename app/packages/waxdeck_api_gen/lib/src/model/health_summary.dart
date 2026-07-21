//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/health_rule_count.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_summary.g.dart';

/// The library's metadata health at the last sweep.
///
/// Properties:
/// * [score] - Library completeness score, 0 to 100: the weighted share of evaluated items passing every rule that applies to them. 
/// * [totalItems] - Items in scope for health.
/// * [evaluatedItems] - Items the sweep has covered so far.
/// * [warmingUp] - True until the sweep first covers the library; the score is provisional while true. 
/// * [sweptAt] - When the last sweep finished.
/// * [rules] - Per-rule failure counts, heaviest first.
@BuiltValue()
abstract class HealthSummary implements Built<HealthSummary, HealthSummaryBuilder> {
  /// Library completeness score, 0 to 100: the weighted share of evaluated items passing every rule that applies to them. 
  @BuiltValueField(wireName: r'score')
  double get score;

  /// Items in scope for health.
  @BuiltValueField(wireName: r'totalItems')
  int get totalItems;

  /// Items the sweep has covered so far.
  @BuiltValueField(wireName: r'evaluatedItems')
  int get evaluatedItems;

  /// True until the sweep first covers the library; the score is provisional while true. 
  @BuiltValueField(wireName: r'warmingUp')
  bool get warmingUp;

  /// When the last sweep finished.
  @BuiltValueField(wireName: r'sweptAt')
  DateTime? get sweptAt;

  /// Per-rule failure counts, heaviest first.
  @BuiltValueField(wireName: r'rules')
  BuiltList<HealthRuleCount> get rules;

  HealthSummary._();

  factory HealthSummary([void updates(HealthSummaryBuilder b)]) = _$HealthSummary;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthSummaryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthSummary> get serializer => _$HealthSummarySerializer();
}

class _$HealthSummarySerializer implements PrimitiveSerializer<HealthSummary> {
  @override
  final Iterable<Type> types = const [HealthSummary, _$HealthSummary];

  @override
  final String wireName = r'HealthSummary';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'score';
    yield serializers.serialize(
      object.score,
      specifiedType: const FullType(double),
    );
    yield r'totalItems';
    yield serializers.serialize(
      object.totalItems,
      specifiedType: const FullType(int),
    );
    yield r'evaluatedItems';
    yield serializers.serialize(
      object.evaluatedItems,
      specifiedType: const FullType(int),
    );
    yield r'warmingUp';
    yield serializers.serialize(
      object.warmingUp,
      specifiedType: const FullType(bool),
    );
    if (object.sweptAt != null) {
      yield r'sweptAt';
      yield serializers.serialize(
        object.sweptAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'rules';
    yield serializers.serialize(
      object.rules,
      specifiedType: const FullType(BuiltList, [FullType(HealthRuleCount)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    HealthSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HealthSummaryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.score = valueDes;
          break;
        case r'totalItems':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalItems = valueDes;
          break;
        case r'evaluatedItems':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.evaluatedItems = valueDes;
          break;
        case r'warmingUp':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.warmingUp = valueDes;
          break;
        case r'sweptAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.sweptAt = valueDes;
          break;
        case r'rules':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(HealthRuleCount)]),
          ) as BuiltList<HealthRuleCount>;
          result.rules.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HealthSummary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthSummaryBuilder();
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

