//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'push_registration_create.g.dart';

/// A UnifiedPush endpoint to register.
///
/// Properties:
/// * [endpoint] - The distributor-issued https endpoint URL.
/// * [label] - Display label, usually the device name.
@BuiltValue()
abstract class PushRegistrationCreate implements Built<PushRegistrationCreate, PushRegistrationCreateBuilder> {
  /// The distributor-issued https endpoint URL.
  @BuiltValueField(wireName: r'endpoint')
  String get endpoint;

  /// Display label, usually the device name.
  @BuiltValueField(wireName: r'label')
  String? get label;

  PushRegistrationCreate._();

  factory PushRegistrationCreate([void updates(PushRegistrationCreateBuilder b)]) = _$PushRegistrationCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PushRegistrationCreateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PushRegistrationCreate> get serializer => _$PushRegistrationCreateSerializer();
}

class _$PushRegistrationCreateSerializer implements PrimitiveSerializer<PushRegistrationCreate> {
  @override
  final Iterable<Type> types = const [PushRegistrationCreate, _$PushRegistrationCreate];

  @override
  final String wireName = r'PushRegistrationCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PushRegistrationCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    PushRegistrationCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PushRegistrationCreateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PushRegistrationCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PushRegistrationCreateBuilder();
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

