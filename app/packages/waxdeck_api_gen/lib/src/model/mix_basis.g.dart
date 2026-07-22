// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mix_basis.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MixBasis _$sonic = const MixBasis._('sonic');
const MixBasis _$metadata = const MixBasis._('metadata');

MixBasis _$valueOf(String name) {
  switch (name) {
    case 'sonic':
      return _$sonic;
    case 'metadata':
      return _$metadata;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MixBasis> _$values = BuiltSet<MixBasis>(const <MixBasis>[
  _$sonic,
  _$metadata,
]);

class _$MixBasisMeta {
  const _$MixBasisMeta();
  MixBasis get sonic => _$sonic;
  MixBasis get metadata => _$metadata;
  MixBasis valueOf(String name) => _$valueOf(name);
  BuiltSet<MixBasis> get values => _$values;
}

mixin _$MixBasisMixin {
  // ignore: non_constant_identifier_names
  _$MixBasisMeta get MixBasis => const _$MixBasisMeta();
}

Serializer<MixBasis> _$mixBasisSerializer = _$MixBasisSerializer();

class _$MixBasisSerializer implements PrimitiveSerializer<MixBasis> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'sonic': 'sonic',
    'metadata': 'metadata',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'sonic': 'sonic',
    'metadata': 'metadata',
  };

  @override
  final Iterable<Type> types = const <Type>[MixBasis];
  @override
  final String wireName = 'MixBasis';

  @override
  Object serialize(
    Serializers serializers,
    MixBasis object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  MixBasis deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => MixBasis.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
