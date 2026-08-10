//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/subscription_settings.dart';
import 'package:waxdeck_api_gen/src/model/podcast_show.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'subscription.g.dart';

/// One subscription of the calling user.
///
/// Properties:
/// * [show_] 
/// * [settings] 
/// * [subscribedAt] - When the caller subscribed.
/// * [unplayedCount] - How many of this show's cataloged episodes the caller has never started: no saved position, and not past the played threshold (which is derived the same way `played` is everywhere else - from the position reached against the episode's duration, never from a listened-milliseconds ratio). Started counts as handled, so a badge stops asking for something already underway; the `unplayed` episode filter and the episode row's own unheard marker use this same definition. The whole backlog, not a window: this is the number a subscription tile shows, and a count drawn from whatever a client had loaded would claim to be the backlog while being a page of it. Counted against the episodes the caller can see, so an explicit episode hidden from this account is not in it. 
@BuiltValue()
abstract class Subscription implements Built<Subscription, SubscriptionBuilder> {
  @BuiltValueField(wireName: r'show')
  PodcastShow get show_;

  @BuiltValueField(wireName: r'settings')
  SubscriptionSettings get settings;

  /// When the caller subscribed.
  @BuiltValueField(wireName: r'subscribedAt')
  DateTime get subscribedAt;

  /// How many of this show's cataloged episodes the caller has never started: no saved position, and not past the played threshold (which is derived the same way `played` is everywhere else - from the position reached against the episode's duration, never from a listened-milliseconds ratio). Started counts as handled, so a badge stops asking for something already underway; the `unplayed` episode filter and the episode row's own unheard marker use this same definition. The whole backlog, not a window: this is the number a subscription tile shows, and a count drawn from whatever a client had loaded would claim to be the backlog while being a page of it. Counted against the episodes the caller can see, so an explicit episode hidden from this account is not in it. 
  @BuiltValueField(wireName: r'unplayedCount')
  int? get unplayedCount;

  Subscription._();

  factory Subscription([void updates(SubscriptionBuilder b)]) = _$Subscription;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SubscriptionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Subscription> get serializer => _$SubscriptionSerializer();
}

class _$SubscriptionSerializer implements PrimitiveSerializer<Subscription> {
  @override
  final Iterable<Type> types = const [Subscription, _$Subscription];

  @override
  final String wireName = r'Subscription';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Subscription object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'show';
    yield serializers.serialize(
      object.show_,
      specifiedType: const FullType(PodcastShow),
    );
    yield r'settings';
    yield serializers.serialize(
      object.settings,
      specifiedType: const FullType(SubscriptionSettings),
    );
    yield r'subscribedAt';
    yield serializers.serialize(
      object.subscribedAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.unplayedCount != null) {
      yield r'unplayedCount';
      yield serializers.serialize(
        object.unplayedCount,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Subscription object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SubscriptionBuilder result,
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
        case r'settings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SubscriptionSettings),
          ) as SubscriptionSettings;
          result.settings.replace(valueDes);
          break;
        case r'subscribedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.subscribedAt = valueDes;
          break;
        case r'unplayedCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.unplayedCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Subscription deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SubscriptionBuilder();
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

