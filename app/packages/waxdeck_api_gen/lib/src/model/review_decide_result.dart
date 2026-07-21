//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/review_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_decide_result.g.dart';

/// The outcome of a single-entry decision.
///
/// Properties:
/// * [entry] 
/// * [warnings] - Non-fatal problems (per-file write-back failures, roles without a tag form). The decision itself stood. 
@BuiltValue()
abstract class ReviewDecideResult implements Built<ReviewDecideResult, ReviewDecideResultBuilder> {
  @BuiltValueField(wireName: r'entry')
  ReviewEntry get entry;

  /// Non-fatal problems (per-file write-back failures, roles without a tag form). The decision itself stood. 
  @BuiltValueField(wireName: r'warnings')
  BuiltList<String>? get warnings;

  ReviewDecideResult._();

  factory ReviewDecideResult([void updates(ReviewDecideResultBuilder b)]) = _$ReviewDecideResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewDecideResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewDecideResult> get serializer => _$ReviewDecideResultSerializer();
}

class _$ReviewDecideResultSerializer implements PrimitiveSerializer<ReviewDecideResult> {
  @override
  final Iterable<Type> types = const [ReviewDecideResult, _$ReviewDecideResult];

  @override
  final String wireName = r'ReviewDecideResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewDecideResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entry';
    yield serializers.serialize(
      object.entry,
      specifiedType: const FullType(ReviewEntry),
    );
    if (object.warnings != null) {
      yield r'warnings';
      yield serializers.serialize(
        object.warnings,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewDecideResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewDecideResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entry':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReviewEntry),
          ) as ReviewEntry;
          result.entry = valueDes;
          break;
        case r'warnings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.warnings.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReviewDecideResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewDecideResultBuilder();
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

