//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'push_registration.g.dart';

/// One UnifiedPush endpoint registration: a compatibility view over a `unifiedpush` notification target. 
///
/// Properties:
/// * [pid] - Type-prefixed ULID (a notification-target pid).
/// * [endpoint] - The distributor-issued push endpoint URL.
/// * [label] - Client-chosen label, usually the device name.
/// * [createdAt] - When the endpoint was registered.
@BuiltValue()
abstract class PushRegistration implements Built<PushRegistration, PushRegistrationBuilder> {
  /// Type-prefixed ULID (a notification-target pid).
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// The distributor-issued push endpoint URL.
  @BuiltValueField(wireName: r'endpoint')
  String get endpoint;

  /// Client-chosen label, usually the device name.
  @BuiltValueField(wireName: r'label')
  String? get label;

  /// When the endpoint was registered.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  PushRegistration._();

  factory PushRegistration([void updates(PushRegistrationBuilder b)]) = _$PushRegistration;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PushRegistrationBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PushRegistration> get serializer => _$PushRegistrationSerializer();
}

class _$PushRegistrationSerializer implements PrimitiveSerializer<PushRegistration> {
  @override
  final Iterable<Type> types = const [PushRegistration, _$PushRegistration];

  @override
  final String wireName = r'PushRegistration';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PushRegistration object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'endpoint';
    yield serializers.serialize(
      object.endpoint,
      specifiedType: const FullType(String),
    );
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType(String),
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
    PushRegistration object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PushRegistrationBuilder result,
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
        case r'endpoint':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.endpoint = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.label = valueDes;
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
  PushRegistration deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PushRegistrationBuilder();
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

