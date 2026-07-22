//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/notification_event.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_event_list.g.dart';

/// The server's notification event catalog.
///
/// Properties:
/// * [events] - Every event this server can emit, server scope first.
@BuiltValue()
abstract class NotificationEventList implements Built<NotificationEventList, NotificationEventListBuilder> {
  /// Every event this server can emit, server scope first.
  @BuiltValueField(wireName: r'events')
  BuiltList<NotificationEvent> get events;

  NotificationEventList._();

  factory NotificationEventList([void updates(NotificationEventListBuilder b)]) = _$NotificationEventList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationEventListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationEventList> get serializer => _$NotificationEventListSerializer();
}

class _$NotificationEventListSerializer implements PrimitiveSerializer<NotificationEventList> {
  @override
  final Iterable<Type> types = const [NotificationEventList, _$NotificationEventList];

  @override
  final String wireName = r'NotificationEventList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationEventList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'events';
    yield serializers.serialize(
      object.events,
      specifiedType: const FullType(BuiltList, [FullType(NotificationEvent)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationEventList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationEventListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'events':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(NotificationEvent)]),
          ) as BuiltList<NotificationEvent>;
          result.events.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationEventList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationEventListBuilder();
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

