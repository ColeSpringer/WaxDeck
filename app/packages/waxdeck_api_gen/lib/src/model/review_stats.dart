//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_stats.g.dart';

/// Queue depth and auto-apply calibration.
///
/// Properties:
/// * [pending] - Entries awaiting a decision.
/// * [identifying] - Entries whose identify pipeline still runs.
/// * [applied] - Entries a person approved.
/// * [autoApplied] - Entries the engine applied on its own.
/// * [asIs] - Entries accepted as they were.
/// * [unofficial] - Entries marked as having no canonical release.
/// * [skipped] - Entries dismissed without action.
/// * [reverted] - Applied entries later reverted, total.
/// * [revertedAutoApplied] - Auto-applied entries later reverted; with `autoApplied` this is the observed auto-apply revert rate, the trust signal the queue surfaces. 
@BuiltValue()
abstract class ReviewStats implements Built<ReviewStats, ReviewStatsBuilder> {
  /// Entries awaiting a decision.
  @BuiltValueField(wireName: r'pending')
  int get pending;

  /// Entries whose identify pipeline still runs.
  @BuiltValueField(wireName: r'identifying')
  int? get identifying;

  /// Entries a person approved.
  @BuiltValueField(wireName: r'applied')
  int get applied;

  /// Entries the engine applied on its own.
  @BuiltValueField(wireName: r'autoApplied')
  int get autoApplied;

  /// Entries accepted as they were.
  @BuiltValueField(wireName: r'asIs')
  int? get asIs;

  /// Entries marked as having no canonical release.
  @BuiltValueField(wireName: r'unofficial')
  int? get unofficial;

  /// Entries dismissed without action.
  @BuiltValueField(wireName: r'skipped')
  int? get skipped;

  /// Applied entries later reverted, total.
  @BuiltValueField(wireName: r'reverted')
  int get reverted;

  /// Auto-applied entries later reverted; with `autoApplied` this is the observed auto-apply revert rate, the trust signal the queue surfaces. 
  @BuiltValueField(wireName: r'revertedAutoApplied')
  int get revertedAutoApplied;

  ReviewStats._();

  factory ReviewStats([void updates(ReviewStatsBuilder b)]) = _$ReviewStats;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewStatsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewStats> get serializer => _$ReviewStatsSerializer();
}

class _$ReviewStatsSerializer implements PrimitiveSerializer<ReviewStats> {
  @override
  final Iterable<Type> types = const [ReviewStats, _$ReviewStats];

  @override
  final String wireName = r'ReviewStats';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewStats object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pending';
    yield serializers.serialize(
      object.pending,
      specifiedType: const FullType(int),
    );
    if (object.identifying != null) {
      yield r'identifying';
      yield serializers.serialize(
        object.identifying,
        specifiedType: const FullType(int),
      );
    }
    yield r'applied';
    yield serializers.serialize(
      object.applied,
      specifiedType: const FullType(int),
    );
    yield r'autoApplied';
    yield serializers.serialize(
      object.autoApplied,
      specifiedType: const FullType(int),
    );
    if (object.asIs != null) {
      yield r'asIs';
      yield serializers.serialize(
        object.asIs,
        specifiedType: const FullType(int),
      );
    }
    if (object.unofficial != null) {
      yield r'unofficial';
      yield serializers.serialize(
        object.unofficial,
        specifiedType: const FullType(int),
      );
    }
    if (object.skipped != null) {
      yield r'skipped';
      yield serializers.serialize(
        object.skipped,
        specifiedType: const FullType(int),
      );
    }
    yield r'reverted';
    yield serializers.serialize(
      object.reverted,
      specifiedType: const FullType(int),
    );
    yield r'revertedAutoApplied';
    yield serializers.serialize(
      object.revertedAutoApplied,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewStats object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewStatsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pending':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.pending = valueDes;
          break;
        case r'identifying':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.identifying = valueDes;
          break;
        case r'applied':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.applied = valueDes;
          break;
        case r'autoApplied':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.autoApplied = valueDes;
          break;
        case r'asIs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.asIs = valueDes;
          break;
        case r'unofficial':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.unofficial = valueDes;
          break;
        case r'skipped':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.skipped = valueDes;
          break;
        case r'reverted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.reverted = valueDes;
          break;
        case r'revertedAutoApplied':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.revertedAutoApplied = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReviewStats deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewStatsBuilder();
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

