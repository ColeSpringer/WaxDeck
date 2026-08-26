//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/library_access.dart';
import 'package:waxdeck_api_gen/src/model/linked_identity.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/permissions.dart';
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
/// * [uploadEnabled] - Whether the account may upload audio. On self views (login, session) this is the *effective* value - administrators always may, whatever their stored flag says - and clients gate their upload affordances on it. On administrative account views (`UserAccount`) it is the stored per-account flag the account editor round-trips; an administrator's own stored flag may therefore read false while their effective right is true. Defined once here because the generators flatten `UserAccount`'s `allOf` over this schema; a duplicate declaration there would silently lose. 
/// * [managePodcasts] - Whether the account may curate podcasts. Self views carry the *effective* value (administrators always may), so clients gate their podcast-curation affordances - adding shows, setting a show's cover - on it without a second read. Absent on administrative account views: the stored per-account flag lives in `permissions` there, and this field would only shadow it. 
/// * [delete] - Whether the account may move visible library items to the recoverable trash. Self views carry the *effective* value (administrators always may), so clients gate destructive affordances - deleting items, a synced playlist's `mirror-trash` mode - on it without a second read. Permanent deletion stays admin-only regardless. Absent on administrative account views: the stored per-account flag lives in `permissions` there, and this field would only shadow it. 
/// * [disabled] - Disabled accounts cannot log in and their live sessions are revoked on disable. 
/// * [pending] - True for a self-serve registration still awaiting an administrator's decision. Pending accounts cannot log in; approve or reject them through the signup request endpoints. 
/// * [libraryAccess] 
/// * [permissions] 
/// * [uploadQuotaBytes] - Bytes the account may hold in upload staging at once, awaiting review; absent means no per-user cap. A pending-upload limit rather than a storage-contribution cap: importing a session releases what it held, and nothing here bounds what the account adds to the library over time. 
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

  @BuiltValueField(wireName: r'permissions')
  Permissions get permissions;

  /// True for a self-serve registration still awaiting an administrator's decision. Pending accounts cannot log in; approve or reject them through the signup request endpoints. 
  @BuiltValueField(wireName: r'pending')
  bool get pending;

  @BuiltValueField(wireName: r'libraryAccess')
  LibraryAccess get libraryAccess;

  /// Disabled accounts cannot log in and their live sessions are revoked on disable. 
  @BuiltValueField(wireName: r'disabled')
  bool get disabled;

  /// Whether local password login is enabled for the account (false for accounts provisioned by OIDC that never set one). 
  @BuiltValueField(wireName: r'hasPassword')
  bool? get hasPassword;

  /// Bytes the account may hold in upload staging at once, awaiting review; absent means no per-user cap. A pending-upload limit rather than a storage-contribution cap: importing a session releases what it held, and nothing here bounds what the account adds to the library over time. 
  @BuiltValueField(wireName: r'uploadQuotaBytes')
  int? get uploadQuotaBytes;

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
    if (object.managePodcasts != null) {
      yield r'managePodcasts';
      yield serializers.serialize(
        object.managePodcasts,
        specifiedType: const FullType(bool),
      );
    }
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
    yield r'pending';
    yield serializers.serialize(
      object.pending,
      specifiedType: const FullType(bool),
    );
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
    if (object.hasPassword != null) {
      yield r'hasPassword';
      yield serializers.serialize(
        object.hasPassword,
        specifiedType: const FullType(bool),
      );
    }
    if (object.delete != null) {
      yield r'delete';
      yield serializers.serialize(
        object.delete,
        specifiedType: const FullType(bool),
      );
    }
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
    yield r'permissions';
    yield serializers.serialize(
      object.permissions,
      specifiedType: const FullType(Permissions),
    );
    yield r'uploadEnabled';
    yield serializers.serialize(
      object.uploadEnabled,
      specifiedType: const FullType(bool),
    );
    yield r'disabled';
    yield serializers.serialize(
      object.disabled,
      specifiedType: const FullType(bool),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    if (object.uploadQuotaBytes != null) {
      yield r'uploadQuotaBytes';
      yield serializers.serialize(
        object.uploadQuotaBytes,
        specifiedType: const FullType(int),
      );
    }
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
        case r'managePodcasts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.managePodcasts = valueDes;
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'pending':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.pending = valueDes;
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
        case r'hasPassword':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasPassword = valueDes;
          break;
        case r'delete':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.delete = valueDes;
          break;
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
        case r'permissions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Permissions),
          ) as Permissions;
          result.permissions.replace(valueDes);
          break;
        case r'uploadEnabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.uploadEnabled = valueDes;
          break;
        case r'disabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.disabled = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'uploadQuotaBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.uploadQuotaBytes = valueDes;
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

