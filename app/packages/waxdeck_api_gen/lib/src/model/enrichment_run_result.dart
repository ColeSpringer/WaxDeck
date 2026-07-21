//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_run_result.g.dart';

/// The started pass.
///
/// Properties:
/// * [jobPid] - The catalog job to follow.
@BuiltValue()
abstract class EnrichmentRunResult implements Built<EnrichmentRunResult, EnrichmentRunResultBuilder> {
  /// The catalog job to follow.
  @BuiltValueField(wireName: r'jobPid')
  String get jobPid;

  EnrichmentRunResult._();

  factory EnrichmentRunResult([void updates(EnrichmentRunResultBuilder b)]) = _$EnrichmentRunResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentRunResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentRunResult> get serializer => _$EnrichmentRunResultSerializer();
}

class _$EnrichmentRunResultSerializer implements PrimitiveSerializer<EnrichmentRunResult> {
  @override
  final Iterable<Type> types = const [EnrichmentRunResult, _$EnrichmentRunResult];

  @override
  final String wireName = r'EnrichmentRunResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentRunResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'jobPid';
    yield serializers.serialize(
      object.jobPid,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentRunResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentRunResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'jobPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.jobPid = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentRunResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentRunResultBuilder();
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

