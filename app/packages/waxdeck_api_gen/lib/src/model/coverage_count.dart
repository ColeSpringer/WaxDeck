//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'coverage_count.g.dart';

/// Enriched versus total for one entity class.
///
/// Properties:
/// * [enriched] - Entities that completed enrichment.
/// * [total] - Entities in scope.
@BuiltValue()
abstract class CoverageCount implements Built<CoverageCount, CoverageCountBuilder> {
  /// Entities that completed enrichment.
  @BuiltValueField(wireName: r'enriched')
  int get enriched;

  /// Entities in scope.
  @BuiltValueField(wireName: r'total')
  int get total;

  CoverageCount._();

  factory CoverageCount([void updates(CoverageCountBuilder b)]) = _$CoverageCount;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CoverageCountBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CoverageCount> get serializer => _$CoverageCountSerializer();
}

class _$CoverageCountSerializer implements PrimitiveSerializer<CoverageCount> {
  @override
  final Iterable<Type> types = const [CoverageCount, _$CoverageCount];

  @override
  final String wireName = r'CoverageCount';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CoverageCount object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'enriched';
    yield serializers.serialize(
      object.enriched,
      specifiedType: const FullType(int),
    );
    yield r'total';
    yield serializers.serialize(
      object.total,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CoverageCount object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CoverageCountBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'enriched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.enriched = valueDes;
          break;
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.total = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CoverageCount deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CoverageCountBuilder();
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

