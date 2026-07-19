//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'transcript_cue.g.dart';

/// One transcript cue.
///
/// Properties:
/// * [startMs] - Cue start in milliseconds.
/// * [endMs] - Cue end in milliseconds, when the format carries one.
/// * [text] - Cue text.
/// * [speaker] - Speaker name, when the format carries one.
@BuiltValue()
abstract class TranscriptCue implements Built<TranscriptCue, TranscriptCueBuilder> {
  /// Cue start in milliseconds.
  @BuiltValueField(wireName: r'startMs')
  int get startMs;

  /// Cue end in milliseconds, when the format carries one.
  @BuiltValueField(wireName: r'endMs')
  int? get endMs;

  /// Cue text.
  @BuiltValueField(wireName: r'text')
  String get text;

  /// Speaker name, when the format carries one.
  @BuiltValueField(wireName: r'speaker')
  String? get speaker;

  TranscriptCue._();

  factory TranscriptCue([void updates(TranscriptCueBuilder b)]) = _$TranscriptCue;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TranscriptCueBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TranscriptCue> get serializer => _$TranscriptCueSerializer();
}

class _$TranscriptCueSerializer implements PrimitiveSerializer<TranscriptCue> {
  @override
  final Iterable<Type> types = const [TranscriptCue, _$TranscriptCue];

  @override
  final String wireName = r'TranscriptCue';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TranscriptCue object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'startMs';
    yield serializers.serialize(
      object.startMs,
      specifiedType: const FullType(int),
    );
    if (object.endMs != null) {
      yield r'endMs';
      yield serializers.serialize(
        object.endMs,
        specifiedType: const FullType(int),
      );
    }
    yield r'text';
    yield serializers.serialize(
      object.text,
      specifiedType: const FullType(String),
    );
    if (object.speaker != null) {
      yield r'speaker';
      yield serializers.serialize(
        object.speaker,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    TranscriptCue object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TranscriptCueBuilder result,
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
        case r'text':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.text = valueDes;
          break;
        case r'speaker':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.speaker = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TranscriptCue deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TranscriptCueBuilder();
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

