// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_media_type.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const UploadMediaType _$music = const UploadMediaType._('music');
const UploadMediaType _$audiobook = const UploadMediaType._('audiobook');
const UploadMediaType _$unknownDefaultOpenApi = const UploadMediaType._(
  'unknownDefaultOpenApi',
);

UploadMediaType _$valueOf(String name) {
  switch (name) {
    case 'music':
      return _$music;
    case 'audiobook':
      return _$audiobook;
    case 'unknownDefaultOpenApi':
      return _$unknownDefaultOpenApi;
    default:
      return _$unknownDefaultOpenApi;
  }
}

final BuiltSet<UploadMediaType> _$values = BuiltSet<UploadMediaType>(
  const <UploadMediaType>[_$music, _$audiobook, _$unknownDefaultOpenApi],
);

class _$UploadMediaTypeMeta {
  const _$UploadMediaTypeMeta();
  UploadMediaType get music => _$music;
  UploadMediaType get audiobook => _$audiobook;
  UploadMediaType get unknownDefaultOpenApi => _$unknownDefaultOpenApi;
  UploadMediaType valueOf(String name) => _$valueOf(name);
  BuiltSet<UploadMediaType> get values => _$values;
}

mixin _$UploadMediaTypeMixin {
  // ignore: non_constant_identifier_names
  _$UploadMediaTypeMeta get UploadMediaType => const _$UploadMediaTypeMeta();
}

Serializer<UploadMediaType> _$uploadMediaTypeSerializer =
    _$UploadMediaTypeSerializer();

class _$UploadMediaTypeSerializer
    implements PrimitiveSerializer<UploadMediaType> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'music': 'music',
    'audiobook': 'audiobook',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'music': 'music',
    'audiobook': 'audiobook',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[UploadMediaType];
  @override
  final String wireName = 'UploadMediaType';

  @override
  Object serialize(
    Serializers serializers,
    UploadMediaType object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  UploadMediaType deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => UploadMediaType.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
