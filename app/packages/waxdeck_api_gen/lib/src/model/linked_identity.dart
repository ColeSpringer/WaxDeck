//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'linked_identity.g.dart';

/// One linked OIDC identity.
///
/// Properties:
/// * [provider] - Provider id the identity belongs to.
/// * [email] - Email reported by the provider at last login, if any.
@BuiltValue()
abstract class LinkedIdentity implements Built<LinkedIdentity, LinkedIdentityBuilder> {
  /// Provider id the identity belongs to.
  @BuiltValueField(wireName: r'provider')
  String get provider;

  /// Email reported by the provider at last login, if any.
  @BuiltValueField(wireName: r'email')
  String? get email;

  LinkedIdentity._();

  factory LinkedIdentity([void updates(LinkedIdentityBuilder b)]) = _$LinkedIdentity;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LinkedIdentityBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LinkedIdentity> get serializer => _$LinkedIdentitySerializer();
}

class _$LinkedIdentitySerializer implements PrimitiveSerializer<LinkedIdentity> {
  @override
  final Iterable<Type> types = const [LinkedIdentity, _$LinkedIdentity];

  @override
  final String wireName = r'LinkedIdentity';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LinkedIdentity object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(String),
    );
    if (object.email != null) {
      yield r'email';
      yield serializers.serialize(
        object.email,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LinkedIdentity object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LinkedIdentityBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.provider = valueDes;
          break;
        case r'email':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.email = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LinkedIdentity deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LinkedIdentityBuilder();
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

