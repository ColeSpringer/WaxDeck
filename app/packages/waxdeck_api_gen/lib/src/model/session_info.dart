//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/user.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'session_info.g.dart';

/// Whether the caller is authenticated, and as whom.
///
/// Properties:
/// * [authenticated] - True when a valid session or token was presented.
/// * [user] 
/// * [csrfToken] - CSRF token for cookie-authenticated mutations. Present only when authenticated. 
@BuiltValue()
abstract class SessionInfo implements Built<SessionInfo, SessionInfoBuilder> {
  /// True when a valid session or token was presented.
  @BuiltValueField(wireName: r'authenticated')
  bool get authenticated;

  @BuiltValueField(wireName: r'user')
  User? get user;

  /// CSRF token for cookie-authenticated mutations. Present only when authenticated. 
  @BuiltValueField(wireName: r'csrfToken')
  String? get csrfToken;

  SessionInfo._();

  factory SessionInfo([void updates(SessionInfoBuilder b)]) = _$SessionInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SessionInfoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SessionInfo> get serializer => _$SessionInfoSerializer();
}

class _$SessionInfoSerializer implements PrimitiveSerializer<SessionInfo> {
  @override
  final Iterable<Type> types = const [SessionInfo, _$SessionInfo];

  @override
  final String wireName = r'SessionInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SessionInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'authenticated';
    yield serializers.serialize(
      object.authenticated,
      specifiedType: const FullType(bool),
    );
    if (object.user != null) {
      yield r'user';
      yield serializers.serialize(
        object.user,
        specifiedType: const FullType(User),
      );
    }
    if (object.csrfToken != null) {
      yield r'csrfToken';
      yield serializers.serialize(
        object.csrfToken,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SessionInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SessionInfoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'authenticated':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.authenticated = valueDes;
          break;
        case r'user':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(User),
          ) as User;
          result.user = valueDes;
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
  SessionInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SessionInfoBuilder();
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

