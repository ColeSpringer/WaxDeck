//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/art_role_info.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/art_source.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'art_roles.g.dart';

/// The artwork slots an entity holds at its own level, and the provenance of the cover a front-cover read would actually answer with. 
///
/// Properties:
/// * [roles] 
/// * [artSource] 
@BuiltValue()
abstract class ArtRoles implements Built<ArtRoles, ArtRolesBuilder> {
  @BuiltValueField(wireName: r'roles')
  BuiltList<ArtRoleInfo> get roles;

  @BuiltValueField(wireName: r'artSource')
  ArtSource? get artSource;

  ArtRoles._();

  factory ArtRoles([void updates(ArtRolesBuilder b)]) = _$ArtRoles;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ArtRolesBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ArtRoles> get serializer => _$ArtRolesSerializer();
}

class _$ArtRolesSerializer implements PrimitiveSerializer<ArtRoles> {
  @override
  final Iterable<Type> types = const [ArtRoles, _$ArtRoles];

  @override
  final String wireName = r'ArtRoles';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ArtRoles object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'roles';
    yield serializers.serialize(
      object.roles,
      specifiedType: const FullType(BuiltList, [FullType(ArtRoleInfo)]),
    );
    if (object.artSource != null) {
      yield r'artSource';
      yield serializers.serialize(
        object.artSource,
        specifiedType: const FullType(ArtSource),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ArtRoles object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ArtRolesBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'roles':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ArtRoleInfo)]),
          ) as BuiltList<ArtRoleInfo>;
          result.roles.replace(valueDes);
          break;
        case r'artSource':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ArtSource),
          ) as ArtSource;
          result.artSource.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ArtRoles deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ArtRolesBuilder();
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

