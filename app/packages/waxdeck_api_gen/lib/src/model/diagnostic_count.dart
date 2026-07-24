//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'diagnostic_count.g.dart';

/// One grouped bucket of the diagnostic summary.
///
/// Properties:
/// * [origin] - The writer that recorded the diagnostics in this bucket.
/// * [code] - The diagnostic code this bucket counts.
/// * [severity] - `info`, `warn`, or `error`.
/// * [count] - How many diagnostics fell in this bucket.
@BuiltValue()
abstract class DiagnosticCount implements Built<DiagnosticCount, DiagnosticCountBuilder> {
  /// The writer that recorded the diagnostics in this bucket.
  @BuiltValueField(wireName: r'origin')
  String get origin;

  /// The diagnostic code this bucket counts.
  @BuiltValueField(wireName: r'code')
  String get code;

  /// `info`, `warn`, or `error`.
  @BuiltValueField(wireName: r'severity')
  String get severity;

  /// How many diagnostics fell in this bucket.
  @BuiltValueField(wireName: r'count')
  int get count;

  DiagnosticCount._();

  factory DiagnosticCount([void updates(DiagnosticCountBuilder b)]) = _$DiagnosticCount;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DiagnosticCountBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DiagnosticCount> get serializer => _$DiagnosticCountSerializer();
}

class _$DiagnosticCountSerializer implements PrimitiveSerializer<DiagnosticCount> {
  @override
  final Iterable<Type> types = const [DiagnosticCount, _$DiagnosticCount];

  @override
  final String wireName = r'DiagnosticCount';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DiagnosticCount object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'origin';
    yield serializers.serialize(
      object.origin,
      specifiedType: const FullType(String),
    );
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
    yield r'severity';
    yield serializers.serialize(
      object.severity,
      specifiedType: const FullType(String),
    );
    yield r'count';
    yield serializers.serialize(
      object.count,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DiagnosticCount object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DiagnosticCountBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'origin':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.origin = valueDes;
          break;
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'severity':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.severity = valueDes;
          break;
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DiagnosticCount deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DiagnosticCountBuilder();
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

