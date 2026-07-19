//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/subscription_settings.dart';
import 'package:waxdeck_api_gen/src/model/podcast_show.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'podcast_detail.g.dart';

/// A show together with the caller's subscription state.
///
/// Properties:
/// * [show_] 
/// * [subscribed] - Whether the calling user follows this show.
/// * [settings] 
@BuiltValue()
abstract class PodcastDetail implements Built<PodcastDetail, PodcastDetailBuilder> {
  @BuiltValueField(wireName: r'show')
  PodcastShow get show_;

  /// Whether the calling user follows this show.
  @BuiltValueField(wireName: r'subscribed')
  bool get subscribed;

  @BuiltValueField(wireName: r'settings')
  SubscriptionSettings? get settings;

  PodcastDetail._();

  factory PodcastDetail([void updates(PodcastDetailBuilder b)]) = _$PodcastDetail;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PodcastDetailBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PodcastDetail> get serializer => _$PodcastDetailSerializer();
}

class _$PodcastDetailSerializer implements PrimitiveSerializer<PodcastDetail> {
  @override
  final Iterable<Type> types = const [PodcastDetail, _$PodcastDetail];

  @override
  final String wireName = r'PodcastDetail';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PodcastDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'show';
    yield serializers.serialize(
      object.show_,
      specifiedType: const FullType(PodcastShow),
    );
    yield r'subscribed';
    yield serializers.serialize(
      object.subscribed,
      specifiedType: const FullType(bool),
    );
    if (object.settings != null) {
      yield r'settings';
      yield serializers.serialize(
        object.settings,
        specifiedType: const FullType(SubscriptionSettings),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PodcastDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PodcastDetailBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'show':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PodcastShow),
          ) as PodcastShow;
          result.show_.replace(valueDes);
          break;
        case r'subscribed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.subscribed = valueDes;
          break;
        case r'settings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SubscriptionSettings),
          ) as SubscriptionSettings;
          result.settings.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PodcastDetail deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PodcastDetailBuilder();
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

