//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/push_registration.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'push_registration_list.g.dart';

/// The caller's push registrations.
///
/// Properties:
/// * [registrations] - Registrations, newest first.
@BuiltValue()
abstract class PushRegistrationList implements Built<PushRegistrationList, PushRegistrationListBuilder> {
  /// Registrations, newest first.
  @BuiltValueField(wireName: r'registrations')
  BuiltList<PushRegistration> get registrations;

  PushRegistrationList._();

  factory PushRegistrationList([void updates(PushRegistrationListBuilder b)]) = _$PushRegistrationList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PushRegistrationListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PushRegistrationList> get serializer => _$PushRegistrationListSerializer();
}

class _$PushRegistrationListSerializer implements PrimitiveSerializer<PushRegistrationList> {
  @override
  final Iterable<Type> types = const [PushRegistrationList, _$PushRegistrationList];

  @override
  final String wireName = r'PushRegistrationList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PushRegistrationList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'registrations';
    yield serializers.serialize(
      object.registrations,
      specifiedType: const FullType(BuiltList, [FullType(PushRegistration)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PushRegistrationList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PushRegistrationListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'registrations':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PushRegistration)]),
          ) as BuiltList<PushRegistration>;
          result.registrations.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PushRegistrationList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PushRegistrationListBuilder();
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

