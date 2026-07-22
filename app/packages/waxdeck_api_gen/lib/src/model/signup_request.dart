//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'signup_request.g.dart';

/// A self-serve registration.
///
/// Properties:
/// * [username] - Requested login name, unique case-insensitively. Leading and trailing whitespace is rejected. 
/// * [password] - The account password (at least 8 characters).
/// * [displayName] - Optional display name.
/// * [inviteToken] - An invite token. A valid one pre-approves the account with the role, access, and permissions the invite carries. 
@BuiltValue()
abstract class SignupRequest implements Built<SignupRequest, SignupRequestBuilder> {
  /// Requested login name, unique case-insensitively. Leading and trailing whitespace is rejected. 
  @BuiltValueField(wireName: r'username')
  String get username;

  /// The account password (at least 8 characters).
  @BuiltValueField(wireName: r'password')
  String get password;

  /// Optional display name.
  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  /// An invite token. A valid one pre-approves the account with the role, access, and permissions the invite carries. 
  @BuiltValueField(wireName: r'inviteToken')
  String? get inviteToken;

  SignupRequest._();

  factory SignupRequest([void updates(SignupRequestBuilder b)]) = _$SignupRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SignupRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SignupRequest> get serializer => _$SignupRequestSerializer();
}

class _$SignupRequestSerializer implements PrimitiveSerializer<SignupRequest> {
  @override
  final Iterable<Type> types = const [SignupRequest, _$SignupRequest];

  @override
  final String wireName = r'SignupRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SignupRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'username';
    yield serializers.serialize(
      object.username,
      specifiedType: const FullType(String),
    );
    yield r'password';
    yield serializers.serialize(
      object.password,
      specifiedType: const FullType(String),
    );
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
    if (object.inviteToken != null) {
      yield r'inviteToken';
      yield serializers.serialize(
        object.inviteToken,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SignupRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SignupRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'username':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.username = valueDes;
          break;
        case r'password':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.password = valueDes;
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'inviteToken':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.inviteToken = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SignupRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SignupRequestBuilder();
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

