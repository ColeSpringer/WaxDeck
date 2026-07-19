//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_config_update.g.dart';

/// Replaces the notification relay configuration.
///
/// Properties:
/// * [appriseUrl] - Apprise API server base URL; empty disables.
/// * [targets] - Apprise target URLs; empty uses the server's own.
/// * [enabledEvents] - Event names to deliver.
@BuiltValue()
abstract class NotificationConfigUpdate implements Built<NotificationConfigUpdate, NotificationConfigUpdateBuilder> {
  /// Apprise API server base URL; empty disables.
  @BuiltValueField(wireName: r'appriseUrl')
  String get appriseUrl;

  /// Apprise target URLs; empty uses the server's own.
  @BuiltValueField(wireName: r'targets')
  String? get targets;

  /// Event names to deliver.
  @BuiltValueField(wireName: r'enabledEvents')
  BuiltList<String> get enabledEvents;

  NotificationConfigUpdate._();

  factory NotificationConfigUpdate([void updates(NotificationConfigUpdateBuilder b)]) = _$NotificationConfigUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationConfigUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationConfigUpdate> get serializer => _$NotificationConfigUpdateSerializer();
}

class _$NotificationConfigUpdateSerializer implements PrimitiveSerializer<NotificationConfigUpdate> {
  @override
  final Iterable<Type> types = const [NotificationConfigUpdate, _$NotificationConfigUpdate];

  @override
  final String wireName = r'NotificationConfigUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationConfigUpdate object, {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationConfigUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationConfigUpdateBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationConfigUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationConfigUpdateBuilder();
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

