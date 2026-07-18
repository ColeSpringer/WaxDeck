//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/library_access.dart';
import 'package:waxdeck_api_gen/src/model/linked_identity.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/user.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'user_account.g.dart';

/// An account as visible to administrators (and to its owner).
///
/// Properties:
/// * [id] - Stable user identifier.
/// * [username] - Login name.
/// * [displayName] - Optional display name; falls back to `username`.
/// * [roles] - Assigned roles (`admin`, `user`).
/// * [disabled] - Disabled accounts cannot log in and their live sessions are revoked on disable. 
/// * [libraryAccess] 
/// * [createdAt] - When the account was created.
/// * [hasPassword] - Whether local password login is enabled for the account (false for accounts provisioned by OIDC that never set one). 
/// * [identities] - Linked single sign-on identities.
@BuiltValue()
abstract class UserAccount implements User, Built<UserAccount, UserAccountBuilder> {
  /// When the account was created.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  /// Linked single sign-on identities.
  @BuiltValueField(wireName: r'identities')
  BuiltList<LinkedIdentity>? get identities;

  @BuiltValueField(wireName: r'libraryAccess')
  LibraryAccess get libraryAccess;

  /// Disabled accounts cannot log in and their live sessions are revoked on disable. 
  @BuiltValueField(wireName: r'disabled')
  bool get disabled;

  /// Whether local password login is enabled for the account (false for accounts provisioned by OIDC that never set one). 
  @BuiltValueField(wireName: r'hasPassword')
  bool? get hasPassword;

  UserAccount._();

  factory UserAccount([void updates(UserAccountBuilder b)]) = _$UserAccount;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UserAccountBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UserAccount> get serializer => _$UserAccountSerializer();
}

class _$UserAccountSerializer implements PrimitiveSerializer<UserAccount> {
  @override
  final Iterable<Type> types = const [UserAccount, _$UserAccount];

  @override
  final String wireName = r'UserAccount';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UserAccount object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.identities != null) {
      yield r'identities';
      yield serializers.serialize(
        object.identities,
        specifiedType: const FullType(BuiltList, [FullType(LinkedIdentity)]),
      );
    }
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
    yield r'roles';
    yield serializers.serialize(
      object.roles,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'libraryAccess';
    yield serializers.serialize(
      object.libraryAccess,
      specifiedType: const FullType(LibraryAccess),
    );
    yield r'disabled';
    yield serializers.serialize(
      object.disabled,
      specifiedType: const FullType(bool),
    );
    if (object.hasPassword != null) {
      yield r'hasPassword';
      yield serializers.serialize(
        object.hasPassword,
        specifiedType: const FullType(bool),
      );
    }
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'username';
    yield serializers.serialize(
      object.username,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UserAccount object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UserAccountBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'identities':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(LinkedIdentity)]),
          ) as BuiltList<LinkedIdentity>;
          result.identities.replace(valueDes);
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'roles':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.roles.replace(valueDes);
          break;
        case r'libraryAccess':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LibraryAccess),
          ) as LibraryAccess;
          result.libraryAccess.replace(valueDes);
          break;
        case r'disabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.disabled = valueDes;
          break;
        case r'hasPassword':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasPassword = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'username':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.username = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UserAccount deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UserAccountBuilder();
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

