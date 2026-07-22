//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/notification_target.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_target_list.g.dart';

/// A scope's notification targets.
///
/// Properties:
/// * [targets] - Targets, newest first.
@BuiltValue()
abstract class NotificationTargetList implements Built<NotificationTargetList, NotificationTargetListBuilder> {
  /// Targets, newest first.
  @BuiltValueField(wireName: r'targets')
  BuiltList<NotificationTarget> get targets;

  NotificationTargetList._();

  factory NotificationTargetList([void updates(NotificationTargetListBuilder b)]) = _$NotificationTargetList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NotificationTargetListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NotificationTargetList> get serializer => _$NotificationTargetListSerializer();
}

class _$NotificationTargetListSerializer implements PrimitiveSerializer<NotificationTargetList> {
  @override
  final Iterable<Type> types = const [NotificationTargetList, _$NotificationTargetList];

  @override
  final String wireName = r'NotificationTargetList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NotificationTargetList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'targets';
    yield serializers.serialize(
      object.targets,
      specifiedType: const FullType(BuiltList, [FullType(NotificationTarget)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    NotificationTargetList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NotificationTargetListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'targets':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(NotificationTarget)]),
          ) as BuiltList<NotificationTarget>;
          result.targets.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NotificationTargetList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NotificationTargetListBuilder();
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

