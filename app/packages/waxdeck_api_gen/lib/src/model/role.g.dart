// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const Role _$admin = const Role._('admin');
const Role _$user = const Role._('user');

Role _$valueOf(String name) {
  switch (name) {
    case 'admin':
      return _$admin;
    case 'user':
      return _$user;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<Role> _$values = BuiltSet<Role>(const <Role>[_$admin, _$user]);

class _$RoleMeta {
  const _$RoleMeta();
  Role get admin => _$admin;
  Role get user => _$user;
  Role valueOf(String name) => _$valueOf(name);
  BuiltSet<Role> get values => _$values;
}

mixin _$RoleMixin {
  // ignore: non_constant_identifier_names
  _$RoleMeta get Role => const _$RoleMeta();
}

Serializer<Role> _$roleSerializer = _$RoleSerializer();

class _$RoleSerializer implements PrimitiveSerializer<Role> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'admin': 'admin',
    'user': 'user',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'admin': 'admin',
    'user': 'user',
  };

  @override
  final Iterable<Type> types = const <Type>[Role];
  @override
  final String wireName = 'Role';

  @override
  Object serialize(
    Serializers serializers,
    Role object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  Role deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => Role.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
