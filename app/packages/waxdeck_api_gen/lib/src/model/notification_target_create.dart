//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/notification_target_kind.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_target_create.g.dart';

/// A notification target to create.
///
/// Properties:
/// * [kind] 
/// * [label] - Display label.
/// * [config] - The kind's delivery configuration (see the NotificationTarget schema for per-kind fields). 
/// * [enabledEvents] - Catalog event names to deliver. Scope rules apply: server-scope targets take server-scope events; user-scope targets take user-scope events, plus server-scope events when the owner is an administrator. 
/// * [muted] - Create the target paused: it delivers nothing but its own per-target tests until unmuted. 
/// * [minIntervalSeconds] - The shortest gap between two deliveries to this target, in seconds. A delivery inside the gap waits rather than spending a retry attempt; the reserved `test` event is exempt, and never starts the gap either. Capped at an hour: that bounds the wait, not the queue, and a target fed faster than its interval has the deliveries it cannot reach inside the outbox's day shed rather than delivered late. 
@BuiltValue()
abstract class NotificationTargetCreate implements Built<NotificationTargetCreate, NotificationTargetCreateBuilder> {
  @BuiltValueField(wireName: r'kind')
  NotificationTargetKind get kind;
  // enum kindEnum {  pushover,  ntfy,  gotify,  discord,  webhook,  apprise,  unifiedpush,  };

  /// Display label.
  @BuiltValueField(wireName: r'label')
  String? get label;

  /// The kind's delivery configuration (see the NotificationTarget schema for per-kind fields). 
  @BuiltValueField(wireName: r'config')
  BuiltMap<String, JsonObject?> get config;

  /// Catalog event names to deliver. Scope rules apply: server-scope targets take server-scope events; user-scope targets take user-scope events, plus server-scope events when the owner is an administrator. 
  @BuiltValueField(wireName: r'enabledEvents')
  BuiltList<String> get enabledEvents;

  /// Create the target paused: it delivers nothing but its own per-target tests until unmuted. 
  @BuiltValueField(wireName: r'muted')
  bool? get muted;

  /// The shortest gap between two deliveries to this target, in seconds. A delivery inside the gap waits rather than spending a retry attempt; the reserved `test` event is exempt, and never starts the gap either. Capped at an hour: that bounds the wait, not the queue, and a target fed faster than its interval has the deliveries it cannot reach inside the outbox's day shed rather than delivered late. 
  @BuiltValueField(wireName: r'minIntervalSeconds')
  int? get minIntervalSeconds;

  NotificationTargetCreate._();

  factory NotificationTargetCreate([void updates(NotificationTargetCreateBuilder b)]) = _$NotificationTargetCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationTargetCreateBuilder b) => b
      ..muted = false
      ..minIntervalSeconds = 0;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationTargetCreate> get serializer => _$NotificationTargetCreateSerializer();
}

class _$NotificationTargetCreateSerializer implements PrimitiveSerializer<NotificationTargetCreate> {
  @override
  final Iterable<Type> types = const [NotificationTargetCreate, _$NotificationTargetCreate];

  @override
  final String wireName = r'NotificationTargetCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationTargetCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(NotificationTargetKind),
    );
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
    NotificationTargetCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationTargetCreateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(NotificationTargetKind),
          ) as NotificationTargetKind;
          result.kind = valueDes;
          break;
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
  NotificationTargetCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationTargetCreateBuilder();
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

