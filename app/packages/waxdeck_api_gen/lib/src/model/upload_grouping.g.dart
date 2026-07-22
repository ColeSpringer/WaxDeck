// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_grouping.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const UploadGrouping _$auto = const UploadGrouping._('auto');
const UploadGrouping _$album = const UploadGrouping._('album');
const UploadGrouping _$tracks = const UploadGrouping._('tracks');

UploadGrouping _$valueOf(String name) {
  switch (name) {
    case 'auto':
      return _$auto;
    case 'album':
      return _$album;
    case 'tracks':
      return _$tracks;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<UploadGrouping> _$values = BuiltSet<UploadGrouping>(
  const <UploadGrouping>[_$auto, _$album, _$tracks],
);

class _$UploadGroupingMeta {
  const _$UploadGroupingMeta();
  UploadGrouping get auto => _$auto;
  UploadGrouping get album => _$album;
  UploadGrouping get tracks => _$tracks;
  UploadGrouping valueOf(String name) => _$valueOf(name);
  BuiltSet<UploadGrouping> get values => _$values;
}

mixin _$UploadGroupingMixin {
  // ignore: non_constant_identifier_names
  _$UploadGroupingMeta get UploadGrouping => const _$UploadGroupingMeta();
}

Serializer<UploadGrouping> _$uploadGroupingSerializer =
    _$UploadGroupingSerializer();

class _$UploadGroupingSerializer
    implements PrimitiveSerializer<UploadGrouping> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'auto': 'auto',
    'album': 'album',
    'tracks': 'tracks',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'auto': 'auto',
    'album': 'album',
    'tracks': 'tracks',
  };

  @override
  final Iterable<Type> types = const <Type>[UploadGrouping];
  @override
  final String wireName = 'UploadGrouping';

  @override
  Object serialize(
    Serializers serializers,
    UploadGrouping object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  UploadGrouping deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => UploadGrouping.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
