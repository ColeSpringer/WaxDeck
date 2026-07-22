//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'media_type_listening.g.dart';

/// Listening total for one media type.
///
/// Properties:
/// * [mediaType] 
/// * [ms] - Milliseconds listened.
/// * [sessions] - Listen sessions.
@BuiltValue()
abstract class MediaTypeListening implements Built<MediaTypeListening, MediaTypeListeningBuilder> {
  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  /// Milliseconds listened.
  @BuiltValueField(wireName: r'ms')
  int get ms;

  /// Listen sessions.
  @BuiltValueField(wireName: r'sessions')
  int get sessions;

  MediaTypeListening._();

  factory MediaTypeListening([void updates(MediaTypeListeningBuilder b)]) = _$MediaTypeListening;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MediaTypeListeningBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MediaTypeListening> get serializer => _$MediaTypeListeningSerializer();
}

class _$MediaTypeListeningSerializer implements PrimitiveSerializer<MediaTypeListening> {
  @override
  final Iterable<Type> types = const [MediaTypeListening, _$MediaTypeListening];

  @override
  final String wireName = r'MediaTypeListening';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MediaTypeListening object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'mediaType';
    yield serializers.serialize(
      object.mediaType,
      specifiedType: const FullType(MediaType),
    );
    yield r'ms';
    yield serializers.serialize(
      object.ms,
      specifiedType: const FullType(int),
    );
    yield r'sessions';
    yield serializers.serialize(
      object.sessions,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MediaTypeListening object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MediaTypeListeningBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'mediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaType),
          ) as MediaType;
          result.mediaType = valueDes;
          break;
        case r'ms':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.ms = valueDes;
          break;
        case r'sessions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sessions = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MediaTypeListening deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MediaTypeListeningBuilder();
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

