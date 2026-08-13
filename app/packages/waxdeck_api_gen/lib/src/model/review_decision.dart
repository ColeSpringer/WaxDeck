//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_decision.g.dart';

/// A decision for one review entry.
///
/// Properties:
/// * [action] - The decision to apply.
/// * [candidateMbid] - The candidate to approve; the ranked best when absent. Only meaningful with `approve`. 
@BuiltValue()
abstract class ReviewDecision implements Built<ReviewDecision, ReviewDecisionBuilder> {
  /// The decision to apply.
  @BuiltValueField(wireName: r'action')
  ReviewDecisionActionEnum get action;
  // enum actionEnum {  approve,  as-is,  unofficial,  skip,  discard,  };

  /// The candidate to approve; the ranked best when absent. Only meaningful with `approve`. 
  @BuiltValueField(wireName: r'candidateMbid')
  String? get candidateMbid;

  ReviewDecision._();

  factory ReviewDecision([void updates(ReviewDecisionBuilder b)]) = _$ReviewDecision;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewDecisionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewDecision> get serializer => _$ReviewDecisionSerializer();
}

class _$ReviewDecisionSerializer implements PrimitiveSerializer<ReviewDecision> {
  @override
  final Iterable<Type> types = const [ReviewDecision, _$ReviewDecision];

  @override
  final String wireName = r'ReviewDecision';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewDecision object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'action';
    yield serializers.serialize(
      object.action,
      specifiedType: const FullType(ReviewDecisionActionEnum),
    );
    if (object.candidateMbid != null) {
      yield r'candidateMbid';
      yield serializers.serialize(
        object.candidateMbid,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewDecision object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewDecisionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'action':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReviewDecisionActionEnum),
          ) as ReviewDecisionActionEnum;
          result.action = valueDes;
          break;
        case r'candidateMbid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.candidateMbid = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReviewDecision deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewDecisionBuilder();
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

class ReviewDecisionActionEnum extends EnumClass {

  /// The decision to apply.
  @BuiltValueEnumConst(wireName: r'approve')
  static const ReviewDecisionActionEnum approve = _$reviewDecisionActionEnum_approve;
  /// The decision to apply.
  @BuiltValueEnumConst(wireName: r'as-is')
  static const ReviewDecisionActionEnum asIs = _$reviewDecisionActionEnum_asIs;
  /// The decision to apply.
  @BuiltValueEnumConst(wireName: r'unofficial')
  static const ReviewDecisionActionEnum unofficial = _$reviewDecisionActionEnum_unofficial;
  /// The decision to apply.
  @BuiltValueEnumConst(wireName: r'skip')
  static const ReviewDecisionActionEnum skip = _$reviewDecisionActionEnum_skip;
  /// The decision to apply.
  @BuiltValueEnumConst(wireName: r'discard')
  static const ReviewDecisionActionEnum discard = _$reviewDecisionActionEnum_discard;
  /// The decision to apply.
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const ReviewDecisionActionEnum unknownDefaultOpenApi = _$reviewDecisionActionEnum_unknownDefaultOpenApi;

  static Serializer<ReviewDecisionActionEnum> get serializer => _$reviewDecisionActionEnumSerializer;

  const ReviewDecisionActionEnum._(String name): super(name);

  static BuiltSet<ReviewDecisionActionEnum> get values => _$reviewDecisionActionEnumValues;
  static ReviewDecisionActionEnum valueOf(String name) => _$reviewDecisionActionEnumValueOf(name);
}

