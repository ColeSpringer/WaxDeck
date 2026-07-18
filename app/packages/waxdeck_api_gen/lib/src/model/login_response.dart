//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/user.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'login_response.g.dart';

/// Established session plus a bearer token for native clients.
///
/// Properties:
/// * [user] 
/// * [token] - Opaque bearer token equivalent to the session cookie. Native clients store it in the OS keychain; web clients ignore it and rely on the cookie. 
/// * [csrfToken] - CSRF token for cookie-authenticated mutations (sent back as the `X-CSRF-Token` header). Irrelevant to bearer-token callers. 
@BuiltValue()
abstract class LoginResponse implements Built<LoginResponse, LoginResponseBuilder> {
  @BuiltValueField(wireName: r'user')
  User get user;

  /// Opaque bearer token equivalent to the session cookie. Native clients store it in the OS keychain; web clients ignore it and rely on the cookie. 
  @BuiltValueField(wireName: r'token')
  String get token;

  /// CSRF token for cookie-authenticated mutations (sent back as the `X-CSRF-Token` header). Irrelevant to bearer-token callers. 
  @BuiltValueField(wireName: r'csrfToken')
  String get csrfToken;

  LoginResponse._();

  factory LoginResponse([void updates(LoginResponseBuilder b)]) = _$LoginResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LoginResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LoginResponse> get serializer => _$LoginResponseSerializer();
}

class _$LoginResponseSerializer implements PrimitiveSerializer<LoginResponse> {
  @override
  final Iterable<Type> types = const [LoginResponse, _$LoginResponse];

  @override
  final String wireName = r'LoginResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LoginResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'user';
    yield serializers.serialize(
      object.user,
      specifiedType: const FullType(User),
    );
    yield r'token';
    yield serializers.serialize(
      object.token,
      specifiedType: const FullType(String),
    );
    yield r'csrfToken';
    yield serializers.serialize(
      object.csrfToken,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LoginResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LoginResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'user':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(User),
          ) as User;
          result.user = valueDes;
          break;
        case r'token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.token = valueDes;
          break;
        case r'csrfToken':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.csrfToken = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LoginResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LoginResponseBuilder();
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

