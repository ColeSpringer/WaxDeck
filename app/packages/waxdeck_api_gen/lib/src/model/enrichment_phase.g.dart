// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrichment_phase.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const EnrichmentPhase _$identity = const EnrichmentPhase._('identity');
const EnrichmentPhase _$releases = const EnrichmentPhase._('releases');
const EnrichmentPhase _$auxArt = const EnrichmentPhase._('auxArt');
const EnrichmentPhase _$artistArt = const EnrichmentPhase._('artistArt');
const EnrichmentPhase _$albumArt = const EnrichmentPhase._('albumArt');
const EnrichmentPhase _$lyrics = const EnrichmentPhase._('lyrics');
const EnrichmentPhase _$trackFields = const EnrichmentPhase._('trackFields');
const EnrichmentPhase _$bookFields = const EnrichmentPhase._('bookFields');
const EnrichmentPhase _$albumFields = const EnrichmentPhase._('albumFields');
const EnrichmentPhase _$unknownDefaultOpenApi = const EnrichmentPhase._(
  'unknownDefaultOpenApi',
);

EnrichmentPhase _$valueOf(String name) {
  switch (name) {
    case 'identity':
      return _$identity;
    case 'releases':
      return _$releases;
    case 'auxArt':
      return _$auxArt;
    case 'artistArt':
      return _$artistArt;
    case 'albumArt':
      return _$albumArt;
    case 'lyrics':
      return _$lyrics;
    case 'trackFields':
      return _$trackFields;
    case 'bookFields':
      return _$bookFields;
    case 'albumFields':
      return _$albumFields;
    case 'unknownDefaultOpenApi':
      return _$unknownDefaultOpenApi;
    default:
      return _$unknownDefaultOpenApi;
  }
}

final BuiltSet<EnrichmentPhase> _$values =
    BuiltSet<EnrichmentPhase>(const <EnrichmentPhase>[
      _$identity,
      _$releases,
      _$auxArt,
      _$artistArt,
      _$albumArt,
      _$lyrics,
      _$trackFields,
      _$bookFields,
      _$albumFields,
      _$unknownDefaultOpenApi,
    ]);

class _$EnrichmentPhaseMeta {
  const _$EnrichmentPhaseMeta();
  EnrichmentPhase get identity => _$identity;
  EnrichmentPhase get releases => _$releases;
  EnrichmentPhase get auxArt => _$auxArt;
  EnrichmentPhase get artistArt => _$artistArt;
  EnrichmentPhase get albumArt => _$albumArt;
  EnrichmentPhase get lyrics => _$lyrics;
  EnrichmentPhase get trackFields => _$trackFields;
  EnrichmentPhase get bookFields => _$bookFields;
  EnrichmentPhase get albumFields => _$albumFields;
  EnrichmentPhase get unknownDefaultOpenApi => _$unknownDefaultOpenApi;
  EnrichmentPhase valueOf(String name) => _$valueOf(name);
  BuiltSet<EnrichmentPhase> get values => _$values;
}

mixin _$EnrichmentPhaseMixin {
  // ignore: non_constant_identifier_names
  _$EnrichmentPhaseMeta get EnrichmentPhase => const _$EnrichmentPhaseMeta();
}

Serializer<EnrichmentPhase> _$enrichmentPhaseSerializer =
    _$EnrichmentPhaseSerializer();

class _$EnrichmentPhaseSerializer
    implements PrimitiveSerializer<EnrichmentPhase> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'identity': 'identity',
    'releases': 'releases',
    'auxArt': 'aux-art',
    'artistArt': 'artist-art',
    'albumArt': 'album-art',
    'lyrics': 'lyrics',
    'trackFields': 'track-fields',
    'bookFields': 'book-fields',
    'albumFields': 'album-fields',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'identity': 'identity',
    'releases': 'releases',
    'aux-art': 'auxArt',
    'artist-art': 'artistArt',
    'album-art': 'albumArt',
    'lyrics': 'lyrics',
    'track-fields': 'trackFields',
    'book-fields': 'bookFields',
    'album-fields': 'albumFields',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[EnrichmentPhase];
  @override
  final String wireName = 'EnrichmentPhase';

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentPhase object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  EnrichmentPhase deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => EnrichmentPhase.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
