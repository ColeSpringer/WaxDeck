// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'art_role.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ArtRole _$front = const ArtRole._('front');
const ArtRole _$back = const ArtRole._('back');
const ArtRole _$disc = const ArtRole._('disc');
const ArtRole _$booklet = const ArtRole._('booklet');
const ArtRole _$background = const ArtRole._('background');
const ArtRole _$unknownDefaultOpenApi = const ArtRole._(
  'unknownDefaultOpenApi',
);

ArtRole _$valueOf(String name) {
  switch (name) {
    case 'front':
      return _$front;
    case 'back':
      return _$back;
    case 'disc':
      return _$disc;
    case 'booklet':
      return _$booklet;
    case 'background':
      return _$background;
    case 'unknownDefaultOpenApi':
      return _$unknownDefaultOpenApi;
    default:
      return _$unknownDefaultOpenApi;
  }
}

final BuiltSet<ArtRole> _$values = BuiltSet<ArtRole>(const <ArtRole>[
  _$front,
  _$back,
  _$disc,
  _$booklet,
  _$background,
  _$unknownDefaultOpenApi,
]);

class _$ArtRoleMeta {
  const _$ArtRoleMeta();
  ArtRole get front => _$front;
  ArtRole get back => _$back;
  ArtRole get disc => _$disc;
  ArtRole get booklet => _$booklet;
  ArtRole get background => _$background;
  ArtRole get unknownDefaultOpenApi => _$unknownDefaultOpenApi;
  ArtRole valueOf(String name) => _$valueOf(name);
  BuiltSet<ArtRole> get values => _$values;
}

mixin _$ArtRoleMixin {
  // ignore: non_constant_identifier_names
  _$ArtRoleMeta get ArtRole => const _$ArtRoleMeta();
}

Serializer<ArtRole> _$artRoleSerializer = _$ArtRoleSerializer();

class _$ArtRoleSerializer implements PrimitiveSerializer<ArtRole> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'front': 'front',
    'back': 'back',
    'disc': 'disc',
    'booklet': 'booklet',
    'background': 'background',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'front': 'front',
    'back': 'back',
    'disc': 'disc',
    'booklet': 'booklet',
    'background': 'background',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[ArtRole];
  @override
  final String wireName = 'ArtRole';

  @override
  Object serialize(
    Serializers serializers,
    ArtRole object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  ArtRole deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => ArtRole.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
