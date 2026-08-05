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

part 'signup_approval.g.dart';

/// What the approved account becomes. Absent fields keep the registration defaults (the `user` role, access to every library, default permissions). 
///
/// Properties:
/// * [roles] - Assigned roles.
/// * [libraryAccess] 
/// * [permissions] 
/// * [uploadEnabled] - Grant upload rights.
/// * [uploadQuotaBytes] - Bytes an account made from this invite may hold in upload staging at once. 
@BuiltValue()
abstract class SignupApproval implements Built<SignupApproval, SignupApprovalBuilder> {
  /// Assigned roles.
  @BuiltValueField(wireName: r'roles')
  BuiltList<Role>? get roles;

  @BuiltValueField(wireName: r'libraryAccess')
  LibraryAccess? get libraryAccess;

  @BuiltValueField(wireName: r'permissions')
  Permissions? get permissions;

  /// Grant upload rights.
  @BuiltValueField(wireName: r'uploadEnabled')
  bool? get uploadEnabled;

  /// Bytes an account made from this invite may hold in upload staging at once. 
  @BuiltValueField(wireName: r'uploadQuotaBytes')
  int? get uploadQuotaBytes;

  SignupApproval._();

  factory SignupApproval([void updates(SignupApprovalBuilder b)]) = _$SignupApproval;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SignupApprovalBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SignupApproval> get serializer => _$SignupApprovalSerializer();
}

class _$SignupApprovalSerializer implements PrimitiveSerializer<SignupApproval> {
  @override
  final Iterable<Type> types = const [SignupApproval, _$SignupApproval];

  @override
  final String wireName = r'SignupApproval';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SignupApproval object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    if (object.uploadQuotaBytes != null) {
      yield r'uploadQuotaBytes';
      yield serializers.serialize(
        object.uploadQuotaBytes,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SignupApproval object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SignupApprovalBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'uploadQuotaBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.uploadQuotaBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SignupApproval deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SignupApprovalBuilder();
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

