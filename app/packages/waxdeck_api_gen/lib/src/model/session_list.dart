//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/device_session.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'session_list.g.dart';

/// The caller's live sessions, newest first.
///
/// Properties:
/// * [sessions] 
@BuiltValue()
abstract class SessionList implements Built<SessionList, SessionListBuilder> {
  @BuiltValueField(wireName: r'sessions')
  BuiltList<DeviceSession> get sessions;

  SessionList._();

  factory SessionList([void updates(SessionListBuilder b)]) = _$SessionList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SessionListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SessionList> get serializer => _$SessionListSerializer();
}

class _$SessionListSerializer implements PrimitiveSerializer<SessionList> {
  @override
  final Iterable<Type> types = const [SessionList, _$SessionList];

  @override
  final String wireName = r'SessionList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SessionList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sessions';
    yield serializers.serialize(
      object.sessions,
      specifiedType: const FullType(BuiltList, [FullType(DeviceSession)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SessionList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SessionListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sessions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DeviceSession)]),
          ) as BuiltList<DeviceSession>;
          result.sessions.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SessionList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SessionListBuilder();
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

