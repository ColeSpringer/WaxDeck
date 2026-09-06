// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_kind.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ScheduleKind _$scan = const ScheduleKind._('scan');
const ScheduleKind _$backup = const ScheduleKind._('backup');
const ScheduleKind _$prune = const ScheduleKind._('prune');
const ScheduleKind _$analyze = const ScheduleKind._('analyze');
const ScheduleKind _$enrich = const ScheduleKind._('enrich');
const ScheduleKind _$unknownDefaultOpenApi = const ScheduleKind._(
  'unknownDefaultOpenApi',
);

ScheduleKind _$valueOf(String name) {
  switch (name) {
    case 'scan':
      return _$scan;
    case 'backup':
      return _$backup;
    case 'prune':
      return _$prune;
    case 'analyze':
      return _$analyze;
    case 'enrich':
      return _$enrich;
    case 'unknownDefaultOpenApi':
      return _$unknownDefaultOpenApi;
    default:
      return _$unknownDefaultOpenApi;
  }
}

final BuiltSet<ScheduleKind> _$values = BuiltSet<ScheduleKind>(
  const <ScheduleKind>[
    _$scan,
    _$backup,
    _$prune,
    _$analyze,
    _$enrich,
    _$unknownDefaultOpenApi,
  ],
);

class _$ScheduleKindMeta {
  const _$ScheduleKindMeta();
  ScheduleKind get scan => _$scan;
  ScheduleKind get backup => _$backup;
  ScheduleKind get prune => _$prune;
  ScheduleKind get analyze => _$analyze;
  ScheduleKind get enrich => _$enrich;
  ScheduleKind get unknownDefaultOpenApi => _$unknownDefaultOpenApi;
  ScheduleKind valueOf(String name) => _$valueOf(name);
  BuiltSet<ScheduleKind> get values => _$values;
}

mixin _$ScheduleKindMixin {
  // ignore: non_constant_identifier_names
  _$ScheduleKindMeta get ScheduleKind => const _$ScheduleKindMeta();
}

Serializer<ScheduleKind> _$scheduleKindSerializer = _$ScheduleKindSerializer();

class _$ScheduleKindSerializer implements PrimitiveSerializer<ScheduleKind> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'scan': 'scan',
    'backup': 'backup',
    'prune': 'prune',
    'analyze': 'analyze',
    'enrich': 'enrich',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'scan': 'scan',
    'backup': 'backup',
    'prune': 'prune',
    'analyze': 'analyze',
    'enrich': 'enrich',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[ScheduleKind];
  @override
  final String wireName = 'ScheduleKind';

  @override
  Object serialize(
    Serializers serializers,
    ScheduleKind object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  ScheduleKind deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => ScheduleKind.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
