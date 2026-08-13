//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'device_session.g.dart';

/// One live session, as shown in the device list.
///
/// Properties:
/// * [id] - Session identifier.
/// * [kind] - `web` sessions authenticate with the cookie; `device` sessions with a bearer token. 
/// * [deviceName] - Client-supplied label, when the login provided one.
/// * [client] - Client software hint (from the login's user agent).
/// * [createdAt] - When the session was established.
/// * [lastSeenAt] - When the session last made a request (coarse, minutes).
/// * [current] - True for the session serving this request.
@BuiltValue()
abstract class DeviceSession implements Built<DeviceSession, DeviceSessionBuilder> {
  /// Session identifier.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// `web` sessions authenticate with the cookie; `device` sessions with a bearer token. 
  @BuiltValueField(wireName: r'kind')
  DeviceSessionKindEnum get kind;
  // enum kindEnum {  web,  device,  };

  /// Client-supplied label, when the login provided one.
  @BuiltValueField(wireName: r'deviceName')
  String? get deviceName;

  /// Client software hint (from the login's user agent).
  @BuiltValueField(wireName: r'client')
  String? get client;

  /// When the session was established.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  /// When the session last made a request (coarse, minutes).
  @BuiltValueField(wireName: r'lastSeenAt')
  DateTime? get lastSeenAt;

  /// True for the session serving this request.
  @BuiltValueField(wireName: r'current')
  bool get current;

  DeviceSession._();

  factory DeviceSession([void updates(DeviceSessionBuilder b)]) = _$DeviceSession;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeviceSessionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeviceSession> get serializer => _$DeviceSessionSerializer();
}

class _$DeviceSessionSerializer implements PrimitiveSerializer<DeviceSession> {
  @override
  final Iterable<Type> types = const [DeviceSession, _$DeviceSession];

  @override
  final String wireName = r'DeviceSession';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeviceSession object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(DeviceSessionKindEnum),
    );
    if (object.deviceName != null) {
      yield r'deviceName';
      yield serializers.serialize(
        object.deviceName,
        specifiedType: const FullType(String),
      );
    }
    if (object.client != null) {
      yield r'client';
      yield serializers.serialize(
        object.client,
        specifiedType: const FullType(String),
      );
    }
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.lastSeenAt != null) {
      yield r'lastSeenAt';
      yield serializers.serialize(
        object.lastSeenAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'current';
    yield serializers.serialize(
      object.current,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DeviceSession object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeviceSessionBuilder result,
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
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DeviceSessionKindEnum),
          ) as DeviceSessionKindEnum;
          result.kind = valueDes;
          break;
        case r'deviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.deviceName = valueDes;
          break;
        case r'client':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.client = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'lastSeenAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastSeenAt = valueDes;
          break;
        case r'current':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.current = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DeviceSession deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeviceSessionBuilder();
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

class DeviceSessionKindEnum extends EnumClass {

  /// `web` sessions authenticate with the cookie; `device` sessions with a bearer token. 
  @BuiltValueEnumConst(wireName: r'web')
  static const DeviceSessionKindEnum web = _$deviceSessionKindEnum_web;
  /// `web` sessions authenticate with the cookie; `device` sessions with a bearer token. 
  @BuiltValueEnumConst(wireName: r'device')
  static const DeviceSessionKindEnum device = _$deviceSessionKindEnum_device;
  /// `web` sessions authenticate with the cookie; `device` sessions with a bearer token. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const DeviceSessionKindEnum unknownDefaultOpenApi = _$deviceSessionKindEnum_unknownDefaultOpenApi;

  static Serializer<DeviceSessionKindEnum> get serializer => _$deviceSessionKindEnumSerializer;

  const DeviceSessionKindEnum._(String name): super(name);

  static BuiltSet<DeviceSessionKindEnum> get values => _$deviceSessionKindEnumValues;
  static DeviceSessionKindEnum valueOf(String name) => _$deviceSessionKindEnumValueOf(name);
}

