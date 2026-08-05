//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/library_access.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/permissions.dart';
import 'package:waxdeck_api_gen/src/model/role.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'user_create.g.dart';

/// A new local account.
///
/// Properties:
/// * [username] - Login name, unique case-insensitively. Leading and trailing whitespace is rejected. 
/// * [password] - Initial password (at least 8 characters).
/// * [displayName] - Optional display name.
/// * [roles] - Assigned roles; defaults to `[user]`.
/// * [libraryAccess] 
/// * [uploadEnabled] - Grant upload rights; defaults to false.
/// * [uploadQuotaBytes] - Bytes the account may hold in upload staging at once; absent means none. An import releases what it held. 
/// * [permissions] 
@BuiltValue()
abstract class UserCreate implements Built<UserCreate, UserCreateBuilder> {
  /// Login name, unique case-insensitively. Leading and trailing whitespace is rejected. 
  @BuiltValueField(wireName: r'username')
  String get username;

  /// Initial password (at least 8 characters).
  @BuiltValueField(wireName: r'password')
  String get password;

  /// Optional display name.
  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  /// Assigned roles; defaults to `[user]`.
  @BuiltValueField(wireName: r'roles')
  BuiltList<Role>? get roles;

  @BuiltValueField(wireName: r'libraryAccess')
  LibraryAccess? get libraryAccess;

  /// Grant upload rights; defaults to false.
  @BuiltValueField(wireName: r'uploadEnabled')
  bool? get uploadEnabled;

  /// Bytes the account may hold in upload staging at once; absent means none. An import releases what it held. 
  @BuiltValueField(wireName: r'uploadQuotaBytes')
  int? get uploadQuotaBytes;

  @BuiltValueField(wireName: r'permissions')
  Permissions? get permissions;

  UserCreate._();

  factory UserCreate([void updates(UserCreateBuilder b)]) = _$UserCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UserCreateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UserCreate> get serializer => _$UserCreateSerializer();
}

class _$UserCreateSerializer implements PrimitiveSerializer<UserCreate> {
  @override
  final Iterable<Type> types = const [UserCreate, _$UserCreate];

  @override
  final String wireName = r'UserCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UserCreate object, {
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
    if (object.roles != null) {
      yield r'roles';
      yield serializers.serialize(
        object.roles,
        specifiedType: const FullType(BuiltList, [FullType(Role)]),
      );
    }
    if (object.libraryAccess != null) {
      yield r'libraryAccess';
      yield serializers.serialize(
        object.libraryAccess,
        specifiedType: const FullType(LibraryAccess),
      );
    }
    if (object.uploadEnabled != null) {
      yield r'uploadEnabled';
      yield serializers.serialize(
        object.uploadEnabled,
        specifiedType: const FullType(bool),
      );
    }
    if (object.uploadQuotaBytes != null) {
      yield r'uploadQuotaBytes';
      yield serializers.serialize(
        object.uploadQuotaBytes,
        specifiedType: const FullType(int),
      );
    }
    if (object.permissions != null) {
      yield r'permissions';
      yield serializers.serialize(
        object.permissions,
        specifiedType: const FullType(Permissions),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UserCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UserCreateBuilder result,
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
        case r'roles':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Role)]),
          ) as BuiltList<Role>;
          result.roles.replace(valueDes);
          break;
        case r'libraryAccess':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LibraryAccess),
          ) as LibraryAccess;
          result.libraryAccess.replace(valueDes);
          break;
        case r'uploadEnabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.uploadEnabled = valueDes;
          break;
        case r'uploadQuotaBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.uploadQuotaBytes = valueDes;
          break;
        case r'permissions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Permissions),
          ) as Permissions;
          result.permissions.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UserCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UserCreateBuilder();
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

