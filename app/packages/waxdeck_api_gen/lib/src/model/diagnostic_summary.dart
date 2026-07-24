//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/diagnostic_count.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'diagnostic_summary.g.dart';

/// Diagnostic counts grouped by writer, code, and severity.
///
/// Properties:
/// * [counts] - Buckets, most severe first.
@BuiltValue()
abstract class DiagnosticSummary implements Built<DiagnosticSummary, DiagnosticSummaryBuilder> {
  /// Buckets, most severe first.
  @BuiltValueField(wireName: r'counts')
  BuiltList<DiagnosticCount> get counts;

  DiagnosticSummary._();

  factory DiagnosticSummary([void updates(DiagnosticSummaryBuilder b)]) = _$DiagnosticSummary;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DiagnosticSummaryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DiagnosticSummary> get serializer => _$DiagnosticSummarySerializer();
}

class _$DiagnosticSummarySerializer implements PrimitiveSerializer<DiagnosticSummary> {
  @override
  final Iterable<Type> types = const [DiagnosticSummary, _$DiagnosticSummary];

  @override
  final String wireName = r'DiagnosticSummary';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DiagnosticSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'counts';
    yield serializers.serialize(
      object.counts,
      specifiedType: const FullType(BuiltList, [FullType(DiagnosticCount)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DiagnosticSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DiagnosticSummaryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'counts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DiagnosticCount)]),
          ) as BuiltList<DiagnosticCount>;
          result.counts.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DiagnosticSummary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DiagnosticSummaryBuilder();
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

