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

part 'invite.g.dart';

/// One invite link's record.
///
/// Properties:
/// * [id] - Invite PID.
/// * [note] - Free-form label (\"for grandma\").
/// * [roles] - Roles the invite assigns.
/// * [libraryAccess] 
/// * [permissions] 
/// * [uploadEnabled] - Whether admitted accounts get upload rights.
/// * [maxUses] - How many accounts the invite admits; 0 is unlimited.
/// * [usedCount] - How many accounts it has admitted.
/// * [revoked] - Whether the invite was revoked.
/// * [expiresAt] - When the token stops working; absent never expires.
/// * [createdAt] - When the invite was created.
/// * [createdBy] - Username of the administrator who created it.
@BuiltValue(instantiable: false)
abstract class Invite  {
  /// Invite PID.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// Free-form label (\"for grandma\").
  @BuiltValueField(wireName: r'note')
  String? get note;

  /// Roles the invite assigns.
  @BuiltValueField(wireName: r'roles')
  BuiltList<Role> get roles;

  @BuiltValueField(wireName: r'libraryAccess')
  LibraryAccess? get libraryAccess;

  @BuiltValueField(wireName: r'permissions')
  Permissions? get permissions;

  /// Whether admitted accounts get upload rights.
  @BuiltValueField(wireName: r'uploadEnabled')
  bool get uploadEnabled;

  /// How many accounts the invite admits; 0 is unlimited.
  @BuiltValueField(wireName: r'maxUses')
  int get maxUses;

  /// How many accounts it has admitted.
  @BuiltValueField(wireName: r'usedCount')
  int get usedCount;

  /// Whether the invite was revoked.
  @BuiltValueField(wireName: r'revoked')
  bool get revoked;

  /// When the token stops working; absent never expires.
  @BuiltValueField(wireName: r'expiresAt')
  DateTime? get expiresAt;

  /// When the invite was created.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  /// Username of the administrator who created it.
  @BuiltValueField(wireName: r'createdBy')
  String? get createdBy;

  @BuiltValueSerializer(custom: true)
  static Serializer<Invite> get serializer => _$InviteSerializer();
}

class _$InviteSerializer implements PrimitiveSerializer<Invite> {
  @override
  final Iterable<Type> types = const [Invite];

  @override
  final String wireName = r'Invite';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Invite object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    if (object.note != null) {
      yield r'note';
      yield serializers.serialize(
        object.note,
        specifiedType: const FullType(String),
      );
    }
    yield r'roles';
    yield serializers.serialize(
      object.roles,
      specifiedType: const FullType(BuiltList, [FullType(Role)]),
    );
    if (object.libraryAccess != null) {
      yield r'libraryAccess';
      yield serializers.serialize(
        object.libraryAccess,
        specifiedType: const FullType(LibraryAccess),
      );
    }
    if (object.permissions != null) {
      yield r'permissions';
      yield serializers.serialize(
        object.permissions,
        specifiedType: const FullType(Permissions),
      );
    }
    yield r'uploadEnabled';
    yield serializers.serialize(
      object.uploadEnabled,
      specifiedType: const FullType(bool),
    );
    yield r'maxUses';
    yield serializers.serialize(
      object.maxUses,
      specifiedType: const FullType(int),
    );
    yield r'usedCount';
    yield serializers.serialize(
      object.usedCount,
      specifiedType: const FullType(int),
    );
    yield r'revoked';
    yield serializers.serialize(
      object.revoked,
      specifiedType: const FullType(bool),
    );
    if (object.expiresAt != null) {
      yield r'expiresAt';
      yield serializers.serialize(
        object.expiresAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.createdBy != null) {
      yield r'createdBy';
      yield serializers.serialize(
        object.createdBy,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Invite object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  Invite deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($Invite)) as $Invite;
  }
}

/// a concrete implementation of [Invite], since [Invite] is not instantiable
@BuiltValue(instantiable: true)
abstract class $Invite implements Invite, Built<$Invite, $InviteBuilder> {
  $Invite._();

  factory $Invite([void Function($InviteBuilder)? updates]) = _$$Invite;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($InviteBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$Invite> get serializer => _$$InviteSerializer();
}

class _$$InviteSerializer implements PrimitiveSerializer<$Invite> {
  @override
  final Iterable<Type> types = const [$Invite, _$$Invite];

  @override
  final String wireName = r'$Invite';

  @override
  Object serialize(
    Serializers serializers,
    $Invite object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(Invite))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InviteBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'note':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.note = valueDes;
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
        case r'maxUses':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.maxUses = valueDes;
          break;
        case r'usedCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.usedCount = valueDes;
          break;
        case r'revoked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.revoked = valueDes;
          break;
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'createdBy':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.createdBy = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  $Invite deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $InviteBuilder();
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

