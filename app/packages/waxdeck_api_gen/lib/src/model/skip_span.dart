//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'skip_span.g.dart';

/// One silence span to skip.
///
/// Properties:
/// * [startMs] - Span start in milliseconds.
/// * [endMs] - Span end in milliseconds, exclusive.
@BuiltValue()
abstract class SkipSpan implements Built<SkipSpan, SkipSpanBuilder> {
  /// Span start in milliseconds.
  @BuiltValueField(wireName: r'startMs')
  int get startMs;

  /// Span end in milliseconds, exclusive.
  @BuiltValueField(wireName: r'endMs')
  int get endMs;

  SkipSpan._();

  factory SkipSpan([void updates(SkipSpanBuilder b)]) = _$SkipSpan;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SkipSpanBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SkipSpan> get serializer => _$SkipSpanSerializer();
}

class _$SkipSpanSerializer implements PrimitiveSerializer<SkipSpan> {
  @override
  final Iterable<Type> types = const [SkipSpan, _$SkipSpan];

  @override
  final String wireName = r'SkipSpan';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SkipSpan object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'startMs';
    yield serializers.serialize(
      object.startMs,
      specifiedType: const FullType(int),
    );
    yield r'endMs';
    yield serializers.serialize(
      object.endMs,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SkipSpan object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SkipSpanBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'startMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.startMs = valueDes;
          break;
        case r'endMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.endMs = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SkipSpan deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SkipSpanBuilder();
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

