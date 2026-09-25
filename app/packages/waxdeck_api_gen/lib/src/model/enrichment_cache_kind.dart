//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_cache_kind.g.dart';

/// One request kind's share of the enrichment cache.
///
/// Properties:
/// * [kind] - The provider and endpoint the answers came from.
/// * [rows] - Cached answers of this kind.
/// * [bytes] - What they cost.
/// * [exempt] - Whether a prune leaves this kind alone.
@BuiltValue()
abstract class EnrichmentCacheKind implements Built<EnrichmentCacheKind, EnrichmentCacheKindBuilder> {
  /// The provider and endpoint the answers came from.
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// Cached answers of this kind.
  @BuiltValueField(wireName: r'rows')
  int get rows;

  /// What they cost.
  @BuiltValueField(wireName: r'bytes')
  int get bytes;

  /// Whether a prune leaves this kind alone.
  @BuiltValueField(wireName: r'exempt')
  bool get exempt;

  EnrichmentCacheKind._();

  factory EnrichmentCacheKind([void updates(EnrichmentCacheKindBuilder b)]) = _$EnrichmentCacheKind;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentCacheKindBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentCacheKind> get serializer => _$EnrichmentCacheKindSerializer();
}

class _$EnrichmentCacheKindSerializer implements PrimitiveSerializer<EnrichmentCacheKind> {
  @override
  final Iterable<Type> types = const [EnrichmentCacheKind, _$EnrichmentCacheKind];

  @override
  final String wireName = r'EnrichmentCacheKind';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentCacheKind object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    yield r'rows';
    yield serializers.serialize(
      object.rows,
      specifiedType: const FullType(int),
    );
    yield r'bytes';
    yield serializers.serialize(
      object.bytes,
      specifiedType: const FullType(int),
    );
    yield r'exempt';
    yield serializers.serialize(
      object.exempt,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentCacheKind object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentCacheKindBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'rows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.rows = valueDes;
          break;
        case r'bytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bytes = valueDes;
          break;
        case r'exempt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.exempt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentCacheKind deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentCacheKindBuilder();
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


