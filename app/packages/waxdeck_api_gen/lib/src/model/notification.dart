//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification.g.dart';

/// One thing that happened to this account. `event` is a catalog event name, so a client words the row itself and stays localized; `title` and `body` are the server's own English wording, for a client that does not know the event. 
///
/// Properties:
/// * [id] - Type-prefixed ULID.
/// * [event] - The catalog event this row reports.
/// * [title] - The server's own one-line wording.
/// * [body] - The server's own detail line.
/// * [targetPid] - What the row is about, when the event names something: the show for `feed-disabled`, the episode for `episode-downloaded`, the playlist for `playlist-synced`, the review entry (`rv-`) for `import-completed`. Absent for events that are about the server rather than an item. 
/// * [createdAt] - When the event happened.
/// * [readAt] - When the row was marked read. Absent while unread.
@BuiltValue()
abstract class Notification implements Built<Notification, NotificationBuilder> {
  /// Type-prefixed ULID.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// The catalog event this row reports.
  @BuiltValueField(wireName: r'event')
  String get event;

  /// The server's own one-line wording.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// The server's own detail line.
  @BuiltValueField(wireName: r'body')
  String get body;

  /// What the row is about, when the event names something: the show for `feed-disabled`, the episode for `episode-downloaded`, the playlist for `playlist-synced`, the review entry (`rv-`) for `import-completed`. Absent for events that are about the server rather than an item. 
  @BuiltValueField(wireName: r'targetPid')
  String? get targetPid;

  /// When the event happened.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  /// When the row was marked read. Absent while unread.
  @BuiltValueField(wireName: r'readAt')
  DateTime? get readAt;

  Notification._();

  factory Notification([void updates(NotificationBuilder b)]) = _$Notification;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Notification> get serializer => _$NotificationSerializer();
}

class _$NotificationSerializer implements PrimitiveSerializer<Notification> {
  @override
  final Iterable<Type> types = const [Notification, _$Notification];

  @override
  final String wireName = r'Notification';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Notification object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'event';
    yield serializers.serialize(
      object.event,
      specifiedType: const FullType(String),
    );
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    yield r'body';
    yield serializers.serialize(
      object.body,
      specifiedType: const FullType(String),
    );
    if (object.targetPid != null) {
      yield r'targetPid';
      yield serializers.serialize(
        object.targetPid,
        specifiedType: const FullType(String),
      );
    }
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.readAt != null) {
      yield r'readAt';
      yield serializers.serialize(
        object.readAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Notification object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'event':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.event = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'body':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.body = valueDes;
          break;
        case r'targetPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targetPid = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'readAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.readAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Notification deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationBuilder();
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

