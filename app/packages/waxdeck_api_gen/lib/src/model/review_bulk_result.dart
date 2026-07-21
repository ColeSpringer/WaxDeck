//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/review_bulk_outcome.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_bulk_result.g.dart';

/// Per-entry outcomes of a bulk decision.
///
/// Properties:
/// * [results] - One outcome per requested entry, in order.
@BuiltValue()
abstract class ReviewBulkResult implements Built<ReviewBulkResult, ReviewBulkResultBuilder> {
  /// One outcome per requested entry, in order.
  @BuiltValueField(wireName: r'results')
  BuiltList<ReviewBulkOutcome> get results;

  ReviewBulkResult._();

  factory ReviewBulkResult([void updates(ReviewBulkResultBuilder b)]) = _$ReviewBulkResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewBulkResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewBulkResult> get serializer => _$ReviewBulkResultSerializer();
}

class _$ReviewBulkResultSerializer implements PrimitiveSerializer<ReviewBulkResult> {
  @override
  final Iterable<Type> types = const [ReviewBulkResult, _$ReviewBulkResult];

  @override
  final String wireName = r'ReviewBulkResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewBulkResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'results';
    yield serializers.serialize(
      object.results,
      specifiedType: const FullType(BuiltList, [FullType(ReviewBulkOutcome)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewBulkResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewBulkResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'results':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ReviewBulkOutcome)]),
          ) as BuiltList<ReviewBulkOutcome>;
          result.results.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReviewBulkResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewBulkResultBuilder();
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

