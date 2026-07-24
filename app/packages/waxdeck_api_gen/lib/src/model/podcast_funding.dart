//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'podcast_funding.g.dart';

/// A show's funding pointer from its feed's `<podcast:funding>` tag: a donation or support URL with the label text the feed suggests. 
///
/// Properties:
/// * [url] - Funding or support URL.
/// * [message] - Suggested call-to-action label for the link.
@BuiltValue()
abstract class PodcastFunding implements Built<PodcastFunding, PodcastFundingBuilder> {
  /// Funding or support URL.
  @BuiltValueField(wireName: r'url')
  String get url;

  /// Suggested call-to-action label for the link.
  @BuiltValueField(wireName: r'message')
  String? get message;

  PodcastFunding._();

  factory PodcastFunding([void updates(PodcastFundingBuilder b)]) = _$PodcastFunding;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PodcastFundingBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PodcastFunding> get serializer => _$PodcastFundingSerializer();
}

class _$PodcastFundingSerializer implements PrimitiveSerializer<PodcastFunding> {
  @override
  final Iterable<Type> types = const [PodcastFunding, _$PodcastFunding];

  @override
  final String wireName = r'PodcastFunding';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PodcastFunding object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'url';
    yield serializers.serialize(
      object.url,
      specifiedType: const FullType(String),
    );
    if (object.message != null) {
      yield r'message';
      yield serializers.serialize(
        object.message,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PodcastFunding object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PodcastFundingBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PodcastFunding deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PodcastFundingBuilder();
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

