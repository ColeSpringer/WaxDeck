//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/transcript_cue.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'transcript.g.dart';

/// An episode's transcript as ordered, time-coded cues.
///
/// Properties:
/// * [format] - Source format the cues were parsed from (`json`, `srt`, `vtt`, `text`). Cues from `text` transcripts carry a zero `startMs` and no `endMs`. 
/// * [cues] - Cues ordered by `startMs`.
@BuiltValue()
abstract class Transcript implements Built<Transcript, TranscriptBuilder> {
  /// Source format the cues were parsed from (`json`, `srt`, `vtt`, `text`). Cues from `text` transcripts carry a zero `startMs` and no `endMs`. 
  @BuiltValueField(wireName: r'format')
  String get format;

  /// Cues ordered by `startMs`.
  @BuiltValueField(wireName: r'cues')
  BuiltList<TranscriptCue> get cues;

  Transcript._();

  factory Transcript([void updates(TranscriptBuilder b)]) = _$Transcript;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TranscriptBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Transcript> get serializer => _$TranscriptSerializer();
}

class _$TranscriptSerializer implements PrimitiveSerializer<Transcript> {
  @override
  final Iterable<Type> types = const [Transcript, _$Transcript];

  @override
  final String wireName = r'Transcript';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Transcript object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'format';
    yield serializers.serialize(
      object.format,
      specifiedType: const FullType(String),
    );
    yield r'cues';
    yield serializers.serialize(
      object.cues,
      specifiedType: const FullType(BuiltList, [FullType(TranscriptCue)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Transcript object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TranscriptBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'format':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.format = valueDes;
          break;
        case r'cues':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TranscriptCue)]),
          ) as BuiltList<TranscriptCue>;
          result.cues.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Transcript deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TranscriptBuilder();
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

