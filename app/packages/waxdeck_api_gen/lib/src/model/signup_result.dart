//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'signup_result.g.dart';

/// What a registration produced.
///
/// Properties:
/// * [state] - `pending` awaits an administrator's approval before it can log in; `active` (invited) can log in immediately. 
@BuiltValue()
abstract class SignupResult implements Built<SignupResult, SignupResultBuilder> {
  /// `pending` awaits an administrator's approval before it can log in; `active` (invited) can log in immediately. 
  @BuiltValueField(wireName: r'state')
  SignupResultStateEnum get state;
  // enum stateEnum {  pending,  active,  };

  SignupResult._();

  factory SignupResult([void updates(SignupResultBuilder b)]) = _$SignupResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SignupResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SignupResult> get serializer => _$SignupResultSerializer();
}

class _$SignupResultSerializer implements PrimitiveSerializer<SignupResult> {
  @override
  final Iterable<Type> types = const [SignupResult, _$SignupResult];

  @override
  final String wireName = r'SignupResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SignupResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'state';
    yield serializers.serialize(
      object.state,
      specifiedType: const FullType(SignupResultStateEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SignupResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SignupResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SignupResultStateEnum),
          ) as SignupResultStateEnum;
          result.state = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SignupResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SignupResultBuilder();
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

class SignupResultStateEnum extends EnumClass {

  /// `pending` awaits an administrator's approval before it can log in; `active` (invited) can log in immediately. 
  @BuiltValueEnumConst(wireName: r'pending')
  static const SignupResultStateEnum pending = _$signupResultStateEnum_pending;
  /// `pending` awaits an administrator's approval before it can log in; `active` (invited) can log in immediately. 
  @BuiltValueEnumConst(wireName: r'active')
  static const SignupResultStateEnum active = _$signupResultStateEnum_active;

  static Serializer<SignupResultStateEnum> get serializer => _$signupResultStateEnumSerializer;

  const SignupResultStateEnum._(String name): super(name);

  static BuiltSet<SignupResultStateEnum> get values => _$signupResultStateEnumValues;
  static SignupResultStateEnum valueOf(String name) => _$signupResultStateEnumValueOf(name);
}

