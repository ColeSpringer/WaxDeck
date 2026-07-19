//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rule_sort.g.dart';

/// One sort key.
///
/// Properties:
/// * [field] - A sortable field from the rule-fields vocabulary.
/// * [desc] - Descending when true.
@BuiltValue()
abstract class RuleSort implements Built<RuleSort, RuleSortBuilder> {
  /// A sortable field from the rule-fields vocabulary.
  @BuiltValueField(wireName: r'field')
  String get field;

  /// Descending when true.
  @BuiltValueField(wireName: r'desc')
  bool? get desc;

  RuleSort._();

  factory RuleSort([void updates(RuleSortBuilder b)]) = _$RuleSort;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RuleSortBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RuleSort> get serializer => _$RuleSortSerializer();
}

class _$RuleSortSerializer implements PrimitiveSerializer<RuleSort> {
  @override
  final Iterable<Type> types = const [RuleSort, _$RuleSort];

  @override
  final String wireName = r'RuleSort';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RuleSort object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'field';
    yield serializers.serialize(
      object.field,
      specifiedType: const FullType(String),
    );
    if (object.desc != null) {
      yield r'desc';
      yield serializers.serialize(
        object.desc,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RuleSort object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RuleSortBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'field':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.field = valueDes;
          break;
        case r'desc':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.desc = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RuleSort deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RuleSortBuilder();
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

