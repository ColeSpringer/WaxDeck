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

part 'invite_create.g.dart';

/// A new invite. Absent fields use the registration defaults (the `user` role, access to every library, default permissions, one use, no expiry). 
///
/// Properties:
/// * [note] - Free-form label.
/// * [roles] - Roles to assign.
/// * [libraryAccess] 
/// * [permissions] 
/// * [uploadEnabled] - Grant upload rights; defaults to false.
/// * [maxUses] - How many accounts it may admit; 0 is unlimited.
/// * [expiresAt] - Expiry; absent never expires.
@BuiltValue()
abstract class InviteCreate implements Built<InviteCreate, InviteCreateBuilder> {
  /// Free-form label.
  @BuiltValueField(wireName: r'note')
  String? get note;

  /// Roles to assign.
  @BuiltValueField(wireName: r'roles')
  BuiltList<Role>? get roles;

  @BuiltValueField(wireName: r'libraryAccess')
  LibraryAccess? get libraryAccess;

  @BuiltValueField(wireName: r'permissions')
  Permissions? get permissions;

  /// Grant upload rights; defaults to false.
  @BuiltValueField(wireName: r'uploadEnabled')
  bool? get uploadEnabled;

  /// How many accounts it may admit; 0 is unlimited.
  @BuiltValueField(wireName: r'maxUses')
  int? get maxUses;

  /// Expiry; absent never expires.
  @BuiltValueField(wireName: r'expiresAt')
  DateTime? get expiresAt;

  InviteCreate._();

  factory InviteCreate([void updates(InviteCreateBuilder b)]) = _$InviteCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InviteCreateBuilder b) => b
      ..maxUses = 1;

  @BuiltValueSerializer(custom: true)
  static Serializer<InviteCreate> get serializer => _$InviteCreateSerializer();
}

class _$InviteCreateSerializer implements PrimitiveSerializer<InviteCreate> {
  @override
  final Iterable<Type> types = const [InviteCreate, _$InviteCreate];

  @override
  final String wireName = r'InviteCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InviteCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.note != null) {
      yield r'note';
      yield serializers.serialize(
        object.note,
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
    if (object.permissions != null) {
      yield r'permissions';
      yield serializers.serialize(
        object.permissions,
        specifiedType: const FullType(Permissions),
      );
    }
    if (object.uploadEnabled != null) {
      yield r'uploadEnabled';
      yield serializers.serialize(
        object.uploadEnabled,
        specifiedType: const FullType(bool),
      );
    }
    if (object.maxUses != null) {
      yield r'maxUses';
      yield serializers.serialize(
        object.maxUses,
        specifiedType: const FullType(int),
      );
    }
    if (object.expiresAt != null) {
      yield r'expiresAt';
      yield serializers.serialize(
        object.expiresAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InviteCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InviteCreateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InviteCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InviteCreateBuilder();
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

