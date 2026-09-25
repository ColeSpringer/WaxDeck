//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/enrichment_phase.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_run_request.g.dart';

/// Options for a whole-library pass.
///
/// Properties:
/// * [force] - Re-enrich entities that already enriched once.
/// * [forcePhases] - Re-ask these phases alone, marked or not, while the rest walk as usual. Refused beside `force` (400), and with `source-unavailable` for a phase this server does not run. 
@BuiltValue()
abstract class EnrichmentRunRequest implements Built<EnrichmentRunRequest, EnrichmentRunRequestBuilder> {
  /// Re-enrich entities that already enriched once.
  @BuiltValueField(wireName: r'force')
  bool? get force;

  /// Re-ask these phases alone, marked or not, while the rest walk as usual. Refused beside `force` (400), and with `source-unavailable` for a phase this server does not run. 
  @BuiltValueField(wireName: r'forcePhases')
  BuiltList<EnrichmentPhase>? get forcePhases;

  EnrichmentRunRequest._();

  factory EnrichmentRunRequest([void updates(EnrichmentRunRequestBuilder b)]) = _$EnrichmentRunRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentRunRequestBuilder b) => b
      ..force = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentRunRequest> get serializer => _$EnrichmentRunRequestSerializer();
}

class _$EnrichmentRunRequestSerializer implements PrimitiveSerializer<EnrichmentRunRequest> {
  @override
  final Iterable<Type> types = const [EnrichmentRunRequest, _$EnrichmentRunRequest];

  @override
  final String wireName = r'EnrichmentRunRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentRunRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.force != null) {
      yield r'force';
      yield serializers.serialize(
        object.force,
        specifiedType: const FullType(bool),
      );
    }
    if (object.forcePhases != null) {
      yield r'forcePhases';
      yield serializers.serialize(
        object.forcePhases,
        specifiedType: const FullType(BuiltList, [FullType(EnrichmentPhase)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentRunRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentRunRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'force':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.force = valueDes;
          break;
        case r'forcePhases':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(EnrichmentPhase)]),
          ) as BuiltList<EnrichmentPhase>?;
          if (valueDes == null) continue;
          result.forcePhases.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentRunRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentRunRequestBuilder();
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


