//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'soundbite.g.dart';

/// One highlight clip of an episode from a `<podcast:soundbite>` tag: a window into the episode audio worth surfacing on its own. 
///
/// Properties:
/// * [startMs] - Clip start offset into the episode, in milliseconds.
/// * [durationMs] - Clip length in milliseconds.
/// * [title] - Clip title; absent means reuse the episode title.
@BuiltValue()
abstract class Soundbite implements Built<Soundbite, SoundbiteBuilder> {
  /// Clip start offset into the episode, in milliseconds.
  @BuiltValueField(wireName: r'startMs')
  int get startMs;

  /// Clip length in milliseconds.
  @BuiltValueField(wireName: r'durationMs')
  int get durationMs;

  /// Clip title; absent means reuse the episode title.
  @BuiltValueField(wireName: r'title')
  String? get title;

  Soundbite._();

  factory Soundbite([void updates(SoundbiteBuilder b)]) = _$Soundbite;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SoundbiteBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Soundbite> get serializer => _$SoundbiteSerializer();
}

class _$SoundbiteSerializer implements PrimitiveSerializer<Soundbite> {
  @override
  final Iterable<Type> types = const [Soundbite, _$Soundbite];

  @override
  final String wireName = r'Soundbite';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Soundbite object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'startMs';
    yield serializers.serialize(
      object.startMs,
      specifiedType: const FullType(int),
    );
    yield r'durationMs';
    yield serializers.serialize(
      object.durationMs,
      specifiedType: const FullType(int),
    );
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Soundbite object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SoundbiteBuilder result,
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
        case r'durationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMs = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Soundbite deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SoundbiteBuilder();
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

