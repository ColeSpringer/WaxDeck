// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_format.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const TimelineFormat _$aac = const TimelineFormat._('aac');
const TimelineFormat _$flac = const TimelineFormat._('flac');
const TimelineFormat _$opus = const TimelineFormat._('opus');
const TimelineFormat _$alac = const TimelineFormat._('alac');
const TimelineFormat _$unknownDefaultOpenApi = const TimelineFormat._(
  'unknownDefaultOpenApi',
);

TimelineFormat _$valueOf(String name) {
  switch (name) {
    case 'aac':
      return _$aac;
    case 'flac':
      return _$flac;
    case 'opus':
      return _$opus;
    case 'alac':
      return _$alac;
    case 'unknownDefaultOpenApi':
      return _$unknownDefaultOpenApi;
    default:
      return _$unknownDefaultOpenApi;
  }
}

final BuiltSet<TimelineFormat> _$values = BuiltSet<TimelineFormat>(
  const <TimelineFormat>[
    _$aac,
    _$flac,
    _$opus,
    _$alac,
    _$unknownDefaultOpenApi,
  ],
);

class _$TimelineFormatMeta {
  const _$TimelineFormatMeta();
  TimelineFormat get aac => _$aac;
  TimelineFormat get flac => _$flac;
  TimelineFormat get opus => _$opus;
  TimelineFormat get alac => _$alac;
  TimelineFormat get unknownDefaultOpenApi => _$unknownDefaultOpenApi;
  TimelineFormat valueOf(String name) => _$valueOf(name);
  BuiltSet<TimelineFormat> get values => _$values;
}

mixin _$TimelineFormatMixin {
  // ignore: non_constant_identifier_names
  _$TimelineFormatMeta get TimelineFormat => const _$TimelineFormatMeta();
}

Serializer<TimelineFormat> _$timelineFormatSerializer =
    _$TimelineFormatSerializer();

class _$TimelineFormatSerializer
    implements PrimitiveSerializer<TimelineFormat> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'aac': 'aac',
    'flac': 'flac',
    'opus': 'opus',
    'alac': 'alac',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'aac': 'aac',
    'flac': 'flac',
    'opus': 'opus',
    'alac': 'alac',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[TimelineFormat];
  @override
  final String wireName = 'TimelineFormat';

  @override
  Object serialize(
    Serializers serializers,
    TimelineFormat object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  TimelineFormat deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => TimelineFormat.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
