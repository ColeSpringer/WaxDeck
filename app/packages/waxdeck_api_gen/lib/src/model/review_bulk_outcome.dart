//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_bulk_outcome.g.dart';

/// One entry's outcome in a bulk decision.
///
/// Properties:
/// * [entryId] - The entry.
/// * [ok] - Whether the decision applied.
/// * [code] - The error code the single-entry decide would have answered (`not-found`, `conflict`, `catalog-busy`, `read-only`, ...), when `ok` is false. `catalog-busy` clears on its own, so those entries can be sent again. 
/// * [error] - Why it did not, when `ok` is false.
/// * [warnings] - What the single-entry decide reports under `warnings`, when `ok` is true: the decision stood, with these problems. 
@BuiltValue()
abstract class ReviewBulkOutcome implements Built<ReviewBulkOutcome, ReviewBulkOutcomeBuilder> {
  /// The entry.
  @BuiltValueField(wireName: r'entryId')
  String get entryId;

  /// Whether the decision applied.
  @BuiltValueField(wireName: r'ok')
  bool get ok;

  /// The error code the single-entry decide would have answered (`not-found`, `conflict`, `catalog-busy`, `read-only`, ...), when `ok` is false. `catalog-busy` clears on its own, so those entries can be sent again. 
  @BuiltValueField(wireName: r'code')
  String? get code;

  /// Why it did not, when `ok` is false.
  @BuiltValueField(wireName: r'error')
  String? get error;

  /// What the single-entry decide reports under `warnings`, when `ok` is true: the decision stood, with these problems. 
  @BuiltValueField(wireName: r'warnings')
  BuiltList<String>? get warnings;

  ReviewBulkOutcome._();

  factory ReviewBulkOutcome([void updates(ReviewBulkOutcomeBuilder b)]) = _$ReviewBulkOutcome;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewBulkOutcomeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewBulkOutcome> get serializer => _$ReviewBulkOutcomeSerializer();
}

class _$ReviewBulkOutcomeSerializer implements PrimitiveSerializer<ReviewBulkOutcome> {
  @override
  final Iterable<Type> types = const [ReviewBulkOutcome, _$ReviewBulkOutcome];

  @override
  final String wireName = r'ReviewBulkOutcome';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewBulkOutcome object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entryId';
    yield serializers.serialize(
      object.entryId,
      specifiedType: const FullType(String),
    );
    yield r'ok';
    yield serializers.serialize(
      object.ok,
      specifiedType: const FullType(bool),
    );
    if (object.code != null) {
      yield r'code';
      yield serializers.serialize(
        object.code,
        specifiedType: const FullType(String),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
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
    ReviewBulkOutcome object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewBulkOutcomeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entryId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.entryId = valueDes;
          break;
        case r'ok':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.ok = valueDes;
          break;
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.code = valueDes;
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.error = valueDes;
          break;
        case r'warnings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
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
  ReviewBulkOutcome deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewBulkOutcomeBuilder();
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


