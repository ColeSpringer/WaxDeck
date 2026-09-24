//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_cache_prune_request.g.dart';

/// Which cached answers to drop. Each bound is optional but one must be given, so a request with neither is refused rather than read as \"everything\". Zero is a value, not an absence. 
///
/// Properties:
/// * [olderThanSeconds] - Drop answers fetched at least this long ago. Absent leaves the age unbounded. 
/// * [maxBytes] - Evict oldest-first until the prunable rows fit this many bytes. Absent leaves the size unbounded. 
@BuiltValue()
abstract class EnrichmentCachePruneRequest implements Built<EnrichmentCachePruneRequest, EnrichmentCachePruneRequestBuilder> {
  /// Drop answers fetched at least this long ago. Absent leaves the age unbounded. 
  @BuiltValueField(wireName: r'olderThanSeconds')
  int? get olderThanSeconds;

  /// Evict oldest-first until the prunable rows fit this many bytes. Absent leaves the size unbounded. 
  @BuiltValueField(wireName: r'maxBytes')
  int? get maxBytes;

  EnrichmentCachePruneRequest._();

  factory EnrichmentCachePruneRequest([void updates(EnrichmentCachePruneRequestBuilder b)]) = _$EnrichmentCachePruneRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentCachePruneRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentCachePruneRequest> get serializer => _$EnrichmentCachePruneRequestSerializer();
}

class _$EnrichmentCachePruneRequestSerializer implements PrimitiveSerializer<EnrichmentCachePruneRequest> {
  @override
  final Iterable<Type> types = const [EnrichmentCachePruneRequest, _$EnrichmentCachePruneRequest];

  @override
  final String wireName = r'EnrichmentCachePruneRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentCachePruneRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.olderThanSeconds != null) {
      yield r'olderThanSeconds';
      yield serializers.serialize(
        object.olderThanSeconds,
        specifiedType: const FullType(int),
      );
    }
    if (object.maxBytes != null) {
      yield r'maxBytes';
      yield serializers.serialize(
        object.maxBytes,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentCachePruneRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentCachePruneRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'olderThanSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.olderThanSeconds = valueDes;
          break;
        case r'maxBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.maxBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentCachePruneRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentCachePruneRequestBuilder();
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

