// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_session.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DeviceSessionKindEnum _$deviceSessionKindEnum_web =
    const DeviceSessionKindEnum._('web');
const DeviceSessionKindEnum _$deviceSessionKindEnum_device =
    const DeviceSessionKindEnum._('device');
const DeviceSessionKindEnum _$deviceSessionKindEnum_unknownDefaultOpenApi =
    const DeviceSessionKindEnum._('unknownDefaultOpenApi');

DeviceSessionKindEnum _$deviceSessionKindEnumValueOf(String name) {
  switch (name) {
    case 'web':
      return _$deviceSessionKindEnum_web;
    case 'device':
      return _$deviceSessionKindEnum_device;
    case 'unknownDefaultOpenApi':
      return _$deviceSessionKindEnum_unknownDefaultOpenApi;
    default:
      return _$deviceSessionKindEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<DeviceSessionKindEnum> _$deviceSessionKindEnumValues =
    BuiltSet<DeviceSessionKindEnum>(const <DeviceSessionKindEnum>[
      _$deviceSessionKindEnum_web,
      _$deviceSessionKindEnum_device,
      _$deviceSessionKindEnum_unknownDefaultOpenApi,
    ]);

Serializer<DeviceSessionKindEnum> _$deviceSessionKindEnumSerializer =
    _$DeviceSessionKindEnumSerializer();

class _$DeviceSessionKindEnumSerializer
    implements PrimitiveSerializer<DeviceSessionKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'web': 'web',
    'device': 'device',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'web': 'web',
    'device': 'device',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[DeviceSessionKindEnum];
  @override
  final String wireName = 'DeviceSessionKindEnum';

  @override
  Object serialize(
    Serializers serializers,
    DeviceSessionKindEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  DeviceSessionKindEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => DeviceSessionKindEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$DeviceSession extends DeviceSession {
  @override
  final String id;
  @override
  final DeviceSessionKindEnum kind;
  @override
  final String? deviceName;
  @override
  final String? client;
  @override
  final DateTime createdAt;
  @override
  final DateTime? lastSeenAt;
  @override
  final bool current;

  factory _$DeviceSession([void Function(DeviceSessionBuilder)? updates]) =>
      (DeviceSessionBuilder()..update(updates))._build();

  _$DeviceSession._({
    required this.id,
    required this.kind,
    this.deviceName,
    this.client,
    required this.createdAt,
    this.lastSeenAt,
    required this.current,
  }) : super._();
  @override
  DeviceSession rebuild(void Function(DeviceSessionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DeviceSessionBuilder toBuilder() => DeviceSessionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DeviceSession &&
        id == other.id &&
        kind == other.kind &&
        deviceName == other.deviceName &&
        client == other.client &&
        createdAt == other.createdAt &&
        lastSeenAt == other.lastSeenAt &&
        current == other.current;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, deviceName.hashCode);
    _$hash = $jc(_$hash, client.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, lastSeenAt.hashCode);
    _$hash = $jc(_$hash, current.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DeviceSession')
          ..add('id', id)
          ..add('kind', kind)
          ..add('deviceName', deviceName)
          ..add('client', client)
          ..add('createdAt', createdAt)
          ..add('lastSeenAt', lastSeenAt)
          ..add('current', current))
        .toString();
  }
}

class DeviceSessionBuilder
    implements Builder<DeviceSession, DeviceSessionBuilder> {
  _$DeviceSession? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  DeviceSessionKindEnum? _kind;
  DeviceSessionKindEnum? get kind => _$this._kind;
  set kind(DeviceSessionKindEnum? kind) => _$this._kind = kind;

  String? _deviceName;
  String? get deviceName => _$this._deviceName;
  set deviceName(String? deviceName) => _$this._deviceName = deviceName;

  String? _client;
  String? get client => _$this._client;
  set client(String? client) => _$this._client = client;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _lastSeenAt;
  DateTime? get lastSeenAt => _$this._lastSeenAt;
  set lastSeenAt(DateTime? lastSeenAt) => _$this._lastSeenAt = lastSeenAt;

  bool? _current;
  bool? get current => _$this._current;
  set current(bool? current) => _$this._current = current;

  DeviceSessionBuilder() {
    DeviceSession._defaults(this);
  }

  DeviceSessionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _kind = $v.kind;
      _deviceName = $v.deviceName;
      _client = $v.client;
      _createdAt = $v.createdAt;
      _lastSeenAt = $v.lastSeenAt;
      _current = $v.current;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DeviceSession other) {
    _$v = other as _$DeviceSession;
  }

  @override
  void update(void Function(DeviceSessionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DeviceSession build() => _build();

  _$DeviceSession _build() {
    final _$result =
        _$v ??
        _$DeviceSession._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'DeviceSession', 'id'),
          kind: BuiltValueNullFieldError.checkNotNull(
            kind,
            r'DeviceSession',
            'kind',
          ),
          deviceName: deviceName,
          client: client,
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'DeviceSession',
            'createdAt',
          ),
          lastSeenAt: lastSeenAt,
          current: BuiltValueNullFieldError.checkNotNull(
            current,
            r'DeviceSession',
            'current',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
