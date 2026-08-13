//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_bulk_decision.g.dart';

/// One decision applied to many entries.
///
/// Properties:
/// * [entryIds] - The entries to decide.
/// * [action] - The decision. `approve` uses each entry's ranked best candidate. 
@BuiltValue()
abstract class ReviewBulkDecision implements Built<ReviewBulkDecision, ReviewBulkDecisionBuilder> {
  /// The entries to decide.
  @BuiltValueField(wireName: r'entryIds')
  BuiltList<String> get entryIds;

  /// The decision. `approve` uses each entry's ranked best candidate. 
  @BuiltValueField(wireName: r'action')
  ReviewBulkDecisionActionEnum get action;
  // enum actionEnum {  approve,  as-is,  unofficial,  skip,  discard,  };

  ReviewBulkDecision._();

  factory ReviewBulkDecision([void updates(ReviewBulkDecisionBuilder b)]) = _$ReviewBulkDecision;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewBulkDecisionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewBulkDecision> get serializer => _$ReviewBulkDecisionSerializer();
}

class _$ReviewBulkDecisionSerializer implements PrimitiveSerializer<ReviewBulkDecision> {
  @override
  final Iterable<Type> types = const [ReviewBulkDecision, _$ReviewBulkDecision];

  @override
  final String wireName = r'ReviewBulkDecision';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewBulkDecision object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entryIds';
    yield serializers.serialize(
      object.entryIds,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'action';
    yield serializers.serialize(
      object.action,
      specifiedType: const FullType(ReviewBulkDecisionActionEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewBulkDecision object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewBulkDecisionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entryIds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.entryIds.replace(valueDes);
          break;
        case r'action':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReviewBulkDecisionActionEnum),
          ) as ReviewBulkDecisionActionEnum;
          result.action = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReviewBulkDecision deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewBulkDecisionBuilder();
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

class ReviewBulkDecisionActionEnum extends EnumClass {

  /// The decision. `approve` uses each entry's ranked best candidate. 
  @BuiltValueEnumConst(wireName: r'approve')
  static const ReviewBulkDecisionActionEnum approve = _$reviewBulkDecisionActionEnum_approve;
  /// The decision. `approve` uses each entry's ranked best candidate. 
  @BuiltValueEnumConst(wireName: r'as-is')
  static const ReviewBulkDecisionActionEnum asIs = _$reviewBulkDecisionActionEnum_asIs;
  /// The decision. `approve` uses each entry's ranked best candidate. 
  @BuiltValueEnumConst(wireName: r'unofficial')
  static const ReviewBulkDecisionActionEnum unofficial = _$reviewBulkDecisionActionEnum_unofficial;
  /// The decision. `approve` uses each entry's ranked best candidate. 
  @BuiltValueEnumConst(wireName: r'skip')
  static const ReviewBulkDecisionActionEnum skip = _$reviewBulkDecisionActionEnum_skip;
  /// The decision. `approve` uses each entry's ranked best candidate. 
  @BuiltValueEnumConst(wireName: r'discard')
  static const ReviewBulkDecisionActionEnum discard = _$reviewBulkDecisionActionEnum_discard;
  /// The decision. `approve` uses each entry's ranked best candidate. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const ReviewBulkDecisionActionEnum unknownDefaultOpenApi = _$reviewBulkDecisionActionEnum_unknownDefaultOpenApi;

  static Serializer<ReviewBulkDecisionActionEnum> get serializer => _$reviewBulkDecisionActionEnumSerializer;

  const ReviewBulkDecisionActionEnum._(String name): super(name);

  static BuiltSet<ReviewBulkDecisionActionEnum> get values => _$reviewBulkDecisionActionEnumValues;
  static ReviewBulkDecisionActionEnum valueOf(String name) => _$reviewBulkDecisionActionEnumValueOf(name);
}

