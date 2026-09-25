//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_cache_prune_result.g.dart';

/// What an enrichment-cache prune dropped.
///
/// Properties:
/// * [removed] - Cached answers dropped.
/// * [freedBytes] - What they held. Freed inside the catalog file rather than returned to the filesystem. 
@BuiltValue()
abstract class EnrichmentCachePruneResult implements Built<EnrichmentCachePruneResult, EnrichmentCachePruneResultBuilder> {
  /// Cached answers dropped.
  @BuiltValueField(wireName: r'removed')
  int get removed;

  /// What they held. Freed inside the catalog file rather than returned to the filesystem. 
  @BuiltValueField(wireName: r'freedBytes')
  int get freedBytes;

  EnrichmentCachePruneResult._();

  factory EnrichmentCachePruneResult([void updates(EnrichmentCachePruneResultBuilder b)]) = _$EnrichmentCachePruneResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentCachePruneResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentCachePruneResult> get serializer => _$EnrichmentCachePruneResultSerializer();
}

class _$EnrichmentCachePruneResultSerializer implements PrimitiveSerializer<EnrichmentCachePruneResult> {
  @override
  final Iterable<Type> types = const [EnrichmentCachePruneResult, _$EnrichmentCachePruneResult];

  @override
  final String wireName = r'EnrichmentCachePruneResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentCachePruneResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'removed';
    yield serializers.serialize(
      object.removed,
      specifiedType: const FullType(int),
    );
    yield r'freedBytes';
    yield serializers.serialize(
      object.freedBytes,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentCachePruneResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentCachePruneResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'removed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.removed = valueDes;
          break;
        case r'freedBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.freedBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentCachePruneResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentCachePruneResultBuilder();
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


