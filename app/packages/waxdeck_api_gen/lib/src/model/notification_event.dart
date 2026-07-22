//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/notification_scope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_event.g.dart';

/// One notification event the server can emit.
///
/// Properties:
/// * [name] - Stable event name.
/// * [scope] 
/// * [description] - Human-readable event description for the checklist.
@BuiltValue()
abstract class NotificationEvent implements Built<NotificationEvent, NotificationEventBuilder> {
  /// Stable event name.
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'scope')
  NotificationScope get scope;
  // enum scopeEnum {  server,  user,  };

  /// Human-readable event description for the checklist.
  @BuiltValueField(wireName: r'description')
  String get description;

  NotificationEvent._();

  factory NotificationEvent([void updates(NotificationEventBuilder b)]) = _$NotificationEvent;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationEventBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationEvent> get serializer => _$NotificationEventSerializer();
}

class _$NotificationEventSerializer implements PrimitiveSerializer<NotificationEvent> {
  @override
  final Iterable<Type> types = const [NotificationEvent, _$NotificationEvent];

  @override
  final String wireName = r'NotificationEvent';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationEvent object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'scope';
    yield serializers.serialize(
      object.scope,
      specifiedType: const FullType(NotificationScope),
    );
    yield r'description';
    yield serializers.serialize(
      object.description,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationEvent object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationEventBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'scope':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(NotificationScope),
          ) as NotificationScope;
          result.scope = valueDes;
          break;
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.description = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationEvent deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationEventBuilder();
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

