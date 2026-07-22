//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/notification_scope.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/notification_target_kind.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_target.g.dart';

/// One notification delivery destination. `config` is a free-form object whose fields depend on `kind` (a discriminated union is deliberately avoided; validation is server-side and per kind, and unknown fields are refused): `pushover` takes `token` (application API token), `userKey`, and optional integer `priority` (-2 quietest to 2 emergency; emergency deliveries use the service's minimum retry cadence); `ntfy` takes `topic`, optional `serverUrl` (default `https://ntfy.sh`), and optional `accessToken` (sent as a Bearer token); `gotify` takes `serverUrl` and `token` (sent as a header, so it stays out of URLs and logs) and optional integer `priority` (0 to 10); `discord` takes `webhookUrl`, which must be a discord.com or discordapp.com webhook URL; `webhook` takes `url` and posts `{event, title, body, timestamp}` as JSON with timestamp in RFC 3339 UTC; `apprise` takes `serverUrl` (the Apprise API server base; its notify endpoint is derived unless the URL already names a path) and optional `targets` (comma or space separated Apprise target URLs; empty relies on the Apprise server's own configuration); `unifiedpush` takes `endpoint` (the distributor-issued https URL, unique per owner). 
///
/// Properties:
/// * [pid] - Type-prefixed ULID.
/// * [kind] 
/// * [scope] 
/// * [label] - Display label, usually the service or device name.
/// * [config] - The kind's delivery configuration, returned verbatim to the owner (see the schema description for per-kind fields). Sealed at rest. 
/// * [enabledEvents] - Catalog event names this target receives. Empty delivers nothing but per-target tests. 
/// * [lastSuccessAt] - When a delivery last succeeded; absent before the first.
/// * [lastError] - The most recent delivery error; absent when the last delivery succeeded.
/// * [lastErrorAt] - When the most recent delivery error happened; cleared, like `lastError`, by a subsequent success. 
/// * [createdAt] - When the target was created.
@BuiltValue()
abstract class NotificationTarget implements Built<NotificationTarget, NotificationTargetBuilder> {
  /// Type-prefixed ULID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  @BuiltValueField(wireName: r'kind')
  NotificationTargetKind get kind;
  // enum kindEnum {  pushover,  ntfy,  gotify,  discord,  webhook,  apprise,  unifiedpush,  };

  @BuiltValueField(wireName: r'scope')
  NotificationScope get scope;
  // enum scopeEnum {  server,  user,  };

  /// Display label, usually the service or device name.
  @BuiltValueField(wireName: r'label')
  String? get label;

  /// The kind's delivery configuration, returned verbatim to the owner (see the schema description for per-kind fields). Sealed at rest. 
  @BuiltValueField(wireName: r'config')
  BuiltMap<String, JsonObject?> get config;

  /// Catalog event names this target receives. Empty delivers nothing but per-target tests. 
  @BuiltValueField(wireName: r'enabledEvents')
  BuiltList<String> get enabledEvents;

  /// When a delivery last succeeded; absent before the first.
  @BuiltValueField(wireName: r'lastSuccessAt')
  DateTime? get lastSuccessAt;

  /// The most recent delivery error; absent when the last delivery succeeded.
  @BuiltValueField(wireName: r'lastError')
  String? get lastError;

  /// When the most recent delivery error happened; cleared, like `lastError`, by a subsequent success. 
  @BuiltValueField(wireName: r'lastErrorAt')
  DateTime? get lastErrorAt;

  /// When the target was created.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  NotificationTarget._();

  factory NotificationTarget([void updates(NotificationTargetBuilder b)]) = _$NotificationTarget;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationTargetBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationTarget> get serializer => _$NotificationTargetSerializer();
}

class _$NotificationTargetSerializer implements PrimitiveSerializer<NotificationTarget> {
  @override
  final Iterable<Type> types = const [NotificationTarget, _$NotificationTarget];

  @override
  final String wireName = r'NotificationTarget';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationTarget object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(NotificationTargetKind),
    );
    yield r'scope';
    yield serializers.serialize(
      object.scope,
      specifiedType: const FullType(NotificationScope),
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
    if (object.lastSuccessAt != null) {
      yield r'lastSuccessAt';
      yield serializers.serialize(
        object.lastSuccessAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.lastError != null) {
      yield r'lastError';
      yield serializers.serialize(
        object.lastError,
        specifiedType: const FullType(String),
      );
    }
    if (object.lastErrorAt != null) {
      yield r'lastErrorAt';
      yield serializers.serialize(
        object.lastErrorAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationTarget object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationTargetBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(NotificationTargetKind),
          ) as NotificationTargetKind;
          result.kind = valueDes;
          break;
        case r'scope':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(NotificationScope),
          ) as NotificationScope;
          result.scope = valueDes;
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
        case r'lastSuccessAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastSuccessAt = valueDes;
          break;
        case r'lastError':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastError = valueDes;
          break;
        case r'lastErrorAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastErrorAt = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationTarget deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationTargetBuilder();
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

