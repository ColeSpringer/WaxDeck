// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acquisition_format.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AcquisitionFormat _$best = const AcquisitionFormat._('best');
const AcquisitionFormat _$opus = const AcquisitionFormat._('opus');
const AcquisitionFormat _$mp3 = const AcquisitionFormat._('mp3');
const AcquisitionFormat _$m4a = const AcquisitionFormat._('m4a');
const AcquisitionFormat _$flac = const AcquisitionFormat._('flac');

AcquisitionFormat _$valueOf(String name) {
  switch (name) {
    case 'best':
      return _$best;
    case 'opus':
      return _$opus;
    case 'mp3':
      return _$mp3;
    case 'm4a':
      return _$m4a;
    case 'flac':
      return _$flac;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AcquisitionFormat> _$values = BuiltSet<AcquisitionFormat>(
  const <AcquisitionFormat>[_$best, _$opus, _$mp3, _$m4a, _$flac],
);

class _$AcquisitionFormatMeta {
  const _$AcquisitionFormatMeta();
  AcquisitionFormat get best => _$best;
  AcquisitionFormat get opus => _$opus;
  AcquisitionFormat get mp3 => _$mp3;
  AcquisitionFormat get m4a => _$m4a;
  AcquisitionFormat get flac => _$flac;
  AcquisitionFormat valueOf(String name) => _$valueOf(name);
  BuiltSet<AcquisitionFormat> get values => _$values;
}

mixin _$AcquisitionFormatMixin {
  // ignore: non_constant_identifier_names
  _$AcquisitionFormatMeta get AcquisitionFormat =>
      const _$AcquisitionFormatMeta();
}

Serializer<AcquisitionFormat> _$acquisitionFormatSerializer =
    _$AcquisitionFormatSerializer();

class _$AcquisitionFormatSerializer
    implements PrimitiveSerializer<AcquisitionFormat> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'best': 'best',
    'opus': 'opus',
    'mp3': 'mp3',
    'm4a': 'm4a',
    'flac': 'flac',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'best': 'best',
    'opus': 'opus',
    'mp3': 'mp3',
    'm4a': 'm4a',
    'flac': 'flac',
  };

  @override
  final Iterable<Type> types = const <Type>[AcquisitionFormat];
  @override
  final String wireName = 'AcquisitionFormat';

  @override
  Object serialize(
    Serializers serializers,
    AcquisitionFormat object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  AcquisitionFormat deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => AcquisitionFormat.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
