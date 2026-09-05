//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_read_request.g.dart';

/// Which inbox rows to mark read.
///
/// Properties:
/// * [ids] - The rows to stamp. Absent or empty marks every unread row read, which is what the \"mark all read\" affordance sends. 
@BuiltValue()
abstract class NotificationReadRequest implements Built<NotificationReadRequest, NotificationReadRequestBuilder> {
  /// The rows to stamp. Absent or empty marks every unread row read, which is what the \"mark all read\" affordance sends. 
  @BuiltValueField(wireName: r'ids')
  BuiltList<String>? get ids;

  NotificationReadRequest._();

  factory NotificationReadRequest([void updates(NotificationReadRequestBuilder b)]) = _$NotificationReadRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationReadRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationReadRequest> get serializer => _$NotificationReadRequestSerializer();
}

class _$NotificationReadRequestSerializer implements PrimitiveSerializer<NotificationReadRequest> {
  @override
  final Iterable<Type> types = const [NotificationReadRequest, _$NotificationReadRequest];

  @override
  final String wireName = r'NotificationReadRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationReadRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.ids != null) {
      yield r'ids';
      yield serializers.serialize(
        object.ids,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationReadRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationReadRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.ids.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationReadRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationReadRequestBuilder();
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

