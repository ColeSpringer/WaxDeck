//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_target_update.g.dart';

/// Replaces a target's label, config, and enabled events; the kind is fixed at creation. `muted` and `minIntervalSeconds` are the exception to the whole-replace: omitting one keeps what the target holds, so a client that predates them cannot wake a destination somebody silenced on purpose just by renaming it. 
///
/// Properties:
/// * [label] - Display label.
/// * [config] - The kind's delivery configuration, replaced whole.
/// * [enabledEvents] - Catalog event names to deliver, under the same scope rules as creation. 
/// * [muted] - Pauses the target: it delivers nothing but its own per-target tests until unmuted. Omitted leaves it as it is. 
/// * [minIntervalSeconds] - The shortest gap between two deliveries to this target, in seconds. A delivery inside the gap waits rather than spending a retry attempt; the reserved `test` event is exempt, and never starts the gap either. Capped at an hour: that bounds the wait, not the queue, and a target fed faster than its interval has the deliveries it cannot reach inside the outbox's day shed rather than delivered late. Omitted leaves it as it is. 
@BuiltValue()
abstract class NotificationTargetUpdate implements Built<NotificationTargetUpdate, NotificationTargetUpdateBuilder> {
  /// Display label.
  @BuiltValueField(wireName: r'label')
  String? get label;

  /// The kind's delivery configuration, replaced whole.
  @BuiltValueField(wireName: r'config')
  BuiltMap<String, JsonObject?> get config;

  /// Catalog event names to deliver, under the same scope rules as creation. 
  @BuiltValueField(wireName: r'enabledEvents')
  BuiltList<String> get enabledEvents;

  /// Pauses the target: it delivers nothing but its own per-target tests until unmuted. Omitted leaves it as it is. 
  @BuiltValueField(wireName: r'muted')
  bool? get muted;

  /// The shortest gap between two deliveries to this target, in seconds. A delivery inside the gap waits rather than spending a retry attempt; the reserved `test` event is exempt, and never starts the gap either. Capped at an hour: that bounds the wait, not the queue, and a target fed faster than its interval has the deliveries it cannot reach inside the outbox's day shed rather than delivered late. Omitted leaves it as it is. 
  @BuiltValueField(wireName: r'minIntervalSeconds')
  int? get minIntervalSeconds;

  NotificationTargetUpdate._();

  factory NotificationTargetUpdate([void updates(NotificationTargetUpdateBuilder b)]) = _$NotificationTargetUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationTargetUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationTargetUpdate> get serializer => _$NotificationTargetUpdateSerializer();
}

class _$NotificationTargetUpdateSerializer implements PrimitiveSerializer<NotificationTargetUpdate> {
  @override
  final Iterable<Type> types = const [NotificationTargetUpdate, _$NotificationTargetUpdate];

  @override
  final String wireName = r'NotificationTargetUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationTargetUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType(String),
      );
    }
    yield r'config';
    yield serializers.serialize(
      object.config,
      specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
    );
    yield r'enabledEvents';
    yield serializers.serialize(
      object.enabledEvents,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.muted != null) {
      yield r'muted';
      yield serializers.serialize(
        object.muted,
        specifiedType: const FullType(bool),
      );
    }
    if (object.minIntervalSeconds != null) {
      yield r'minIntervalSeconds';
      yield serializers.serialize(
        object.minIntervalSeconds,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationTargetUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationTargetUpdateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.label = valueDes;
          break;
        case r'config':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
          ) as BuiltMap<String, JsonObject?>;
          result.config.replace(valueDes);
          break;
        case r'enabledEvents':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.enabledEvents.replace(valueDes);
          break;
        case r'muted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.muted = valueDes;
          break;
        case r'minIntervalSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.minIntervalSeconds = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationTargetUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationTargetUpdateBuilder();
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

