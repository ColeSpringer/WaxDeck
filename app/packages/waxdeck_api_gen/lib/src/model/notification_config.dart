//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_config.g.dart';

/// The server's notification relay configuration.
///
/// Properties:
/// * [appriseUrl] - Base URL of the Apprise API server to relay through (its notify endpoint is derived). Empty disables Apprise delivery. 
/// * [targets] - Apprise target URLs (comma or space separated) passed with each notification. Empty relies on the Apprise server's own configured targets. 
/// * [enabledEvents] - Event names to deliver.
/// * [knownEvents] - The server's current event catalog, for building the settings surface. 
@BuiltValue()
abstract class NotificationConfig implements Built<NotificationConfig, NotificationConfigBuilder> {
  /// Base URL of the Apprise API server to relay through (its notify endpoint is derived). Empty disables Apprise delivery. 
  @BuiltValueField(wireName: r'appriseUrl')
  String get appriseUrl;

  /// Apprise target URLs (comma or space separated) passed with each notification. Empty relies on the Apprise server's own configured targets. 
  @BuiltValueField(wireName: r'targets')
  String? get targets;

  /// Event names to deliver.
  @BuiltValueField(wireName: r'enabledEvents')
  BuiltList<String> get enabledEvents;

  /// The server's current event catalog, for building the settings surface. 
  @BuiltValueField(wireName: r'knownEvents')
  BuiltList<String> get knownEvents;

  NotificationConfig._();

  factory NotificationConfig([void updates(NotificationConfigBuilder b)]) = _$NotificationConfig;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationConfigBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationConfig> get serializer => _$NotificationConfigSerializer();
}

class _$NotificationConfigSerializer implements PrimitiveSerializer<NotificationConfig> {
  @override
  final Iterable<Type> types = const [NotificationConfig, _$NotificationConfig];

  @override
  final String wireName = r'NotificationConfig';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'appriseUrl';
    yield serializers.serialize(
      object.appriseUrl,
      specifiedType: const FullType(String),
    );
    if (object.targets != null) {
      yield r'targets';
      yield serializers.serialize(
        object.targets,
        specifiedType: const FullType(String),
      );
    }
    yield r'enabledEvents';
    yield serializers.serialize(
      object.enabledEvents,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'knownEvents';
    yield serializers.serialize(
      object.knownEvents,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationConfigBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'appriseUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.appriseUrl = valueDes;
          break;
        case r'targets':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targets = valueDes;
          break;
        case r'enabledEvents':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.enabledEvents.replace(valueDes);
          break;
        case r'knownEvents':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.knownEvents.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationConfig deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationConfigBuilder();
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

