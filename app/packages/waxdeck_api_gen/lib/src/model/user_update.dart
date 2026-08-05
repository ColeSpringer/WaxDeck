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

part 'user_update.g.dart';

/// Partial account update: absent fields are unchanged. Setting `displayName` to the empty string clears it. 
///
/// Properties:
/// * [displayName] - New display name; empty clears it.
/// * [roles] - Replacement role set.
/// * [disabled] - Disable or re-enable the account. Disabling revokes its live sessions. 
/// * [libraryAccess] 
/// * [uploadEnabled] - Grant or revoke upload rights.
/// * [uploadQuotaBytes] - New ceiling on bytes held in upload staging at once; 0 removes it. 
/// * [permissions] 
@BuiltValue()
abstract class UserUpdate implements Built<UserUpdate, UserUpdateBuilder> {
  /// New display name; empty clears it.
  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  /// Replacement role set.
  @BuiltValueField(wireName: r'roles')
  BuiltList<Role>? get roles;

  /// Disable or re-enable the account. Disabling revokes its live sessions. 
  @BuiltValueField(wireName: r'disabled')
  bool? get disabled;

  @BuiltValueField(wireName: r'libraryAccess')
  LibraryAccess? get libraryAccess;

  /// Grant or revoke upload rights.
  @BuiltValueField(wireName: r'uploadEnabled')
  bool? get uploadEnabled;

  /// New ceiling on bytes held in upload staging at once; 0 removes it. 
  @BuiltValueField(wireName: r'uploadQuotaBytes')
  int? get uploadQuotaBytes;

  @BuiltValueField(wireName: r'permissions')
  Permissions? get permissions;

  UserUpdate._();

  factory UserUpdate([void updates(UserUpdateBuilder b)]) = _$UserUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UserUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UserUpdate> get serializer => _$UserUpdateSerializer();
}

class _$UserUpdateSerializer implements PrimitiveSerializer<UserUpdate> {
  @override
  final Iterable<Type> types = const [UserUpdate, _$UserUpdate];

  @override
  final String wireName = r'UserUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UserUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    if (object.disabled != null) {
      yield r'disabled';
      yield serializers.serialize(
        object.disabled,
        specifiedType: const FullType(bool),
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
    UserUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UserUpdateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'disabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.disabled = valueDes;
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
  UserUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UserUpdateBuilder();
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

