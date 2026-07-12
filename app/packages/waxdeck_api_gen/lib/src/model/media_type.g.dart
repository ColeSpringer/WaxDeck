// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_type.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MediaType _$music = const MediaType._('music');
const MediaType _$podcast = const MediaType._('podcast');
const MediaType _$audiobook = const MediaType._('audiobook');

MediaType _$valueOf(String name) {
  switch (name) {
    case 'music':
      return _$music;
    case 'podcast':
      return _$podcast;
    case 'audiobook':
      return _$audiobook;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MediaType> _$values = BuiltSet<MediaType>(const <MediaType>[
  _$music,
  _$podcast,
  _$audiobook,
]);

class _$MediaTypeMeta {
  const _$MediaTypeMeta();
  MediaType get music => _$music;
  MediaType get podcast => _$podcast;
  MediaType get audiobook => _$audiobook;
  MediaType valueOf(String name) => _$valueOf(name);
  BuiltSet<MediaType> get values => _$values;
}

mixin _$MediaTypeMixin {
  // ignore: non_constant_identifier_names
  _$MediaTypeMeta get MediaType => const _$MediaTypeMeta();
}

Serializer<MediaType> _$mediaTypeSerializer = _$MediaTypeSerializer();

class _$MediaTypeSerializer implements PrimitiveSerializer<MediaType> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'music': 'music',
    'podcast': 'podcast',
    'audiobook': 'audiobook',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'music': 'music',
    'podcast': 'podcast',
    'audiobook': 'audiobook',
  };

  @override
  final Iterable<Type> types = const <Type>[MediaType];
  @override
  final String wireName = 'MediaType';

  @override
  Object serialize(
    Serializers serializers,
    MediaType object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  MediaType deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => MediaType.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
