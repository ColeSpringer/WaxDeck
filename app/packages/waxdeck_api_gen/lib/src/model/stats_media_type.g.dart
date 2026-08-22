// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stats_media_type.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const StatsMediaType _$music = const StatsMediaType._('music');
const StatsMediaType _$podcast = const StatsMediaType._('podcast');
const StatsMediaType _$audiobook = const StatsMediaType._('audiobook');
const StatsMediaType _$radio = const StatsMediaType._('radio');
const StatsMediaType _$unknownDefaultOpenApi = const StatsMediaType._(
  'unknownDefaultOpenApi',
);

StatsMediaType _$valueOf(String name) {
  switch (name) {
    case 'music':
      return _$music;
    case 'podcast':
      return _$podcast;
    case 'audiobook':
      return _$audiobook;
    case 'radio':
      return _$radio;
    case 'unknownDefaultOpenApi':
      return _$unknownDefaultOpenApi;
    default:
      return _$unknownDefaultOpenApi;
  }
}

final BuiltSet<StatsMediaType> _$values = BuiltSet<StatsMediaType>(
  const <StatsMediaType>[
    _$music,
    _$podcast,
    _$audiobook,
    _$radio,
    _$unknownDefaultOpenApi,
  ],
);

class _$StatsMediaTypeMeta {
  const _$StatsMediaTypeMeta();
  StatsMediaType get music => _$music;
  StatsMediaType get podcast => _$podcast;
  StatsMediaType get audiobook => _$audiobook;
  StatsMediaType get radio => _$radio;
  StatsMediaType get unknownDefaultOpenApi => _$unknownDefaultOpenApi;
  StatsMediaType valueOf(String name) => _$valueOf(name);
  BuiltSet<StatsMediaType> get values => _$values;
}

mixin _$StatsMediaTypeMixin {
  // ignore: non_constant_identifier_names
  _$StatsMediaTypeMeta get StatsMediaType => const _$StatsMediaTypeMeta();
}

Serializer<StatsMediaType> _$statsMediaTypeSerializer =
    _$StatsMediaTypeSerializer();

class _$StatsMediaTypeSerializer
    implements PrimitiveSerializer<StatsMediaType> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'music': 'music',
    'podcast': 'podcast',
    'audiobook': 'audiobook',
    'radio': 'radio',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'music': 'music',
    'podcast': 'podcast',
    'audiobook': 'audiobook',
    'radio': 'radio',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[StatsMediaType];
  @override
  final String wireName = 'StatsMediaType';

  @override
  Object serialize(
    Serializers serializers,
    StatsMediaType object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  StatsMediaType deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => StatsMediaType.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
