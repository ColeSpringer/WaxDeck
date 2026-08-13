// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_scope.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const NotificationScope _$server = const NotificationScope._('server');
const NotificationScope _$user = const NotificationScope._('user');
const NotificationScope _$unknownDefaultOpenApi = const NotificationScope._(
  'unknownDefaultOpenApi',
);

NotificationScope _$valueOf(String name) {
  switch (name) {
    case 'server':
      return _$server;
    case 'user':
      return _$user;
    case 'unknownDefaultOpenApi':
      return _$unknownDefaultOpenApi;
    default:
      return _$unknownDefaultOpenApi;
  }
}

final BuiltSet<NotificationScope> _$values = BuiltSet<NotificationScope>(
  const <NotificationScope>[_$server, _$user, _$unknownDefaultOpenApi],
);

class _$NotificationScopeMeta {
  const _$NotificationScopeMeta();
  NotificationScope get server => _$server;
  NotificationScope get user => _$user;
  NotificationScope get unknownDefaultOpenApi => _$unknownDefaultOpenApi;
  NotificationScope valueOf(String name) => _$valueOf(name);
  BuiltSet<NotificationScope> get values => _$values;
}

mixin _$NotificationScopeMixin {
  // ignore: non_constant_identifier_names
  _$NotificationScopeMeta get NotificationScope =>
      const _$NotificationScopeMeta();
}

Serializer<NotificationScope> _$notificationScopeSerializer =
    _$NotificationScopeSerializer();

class _$NotificationScopeSerializer
    implements PrimitiveSerializer<NotificationScope> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'server': 'server',
    'user': 'user',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'server': 'server',
    'user': 'user',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[NotificationScope];
  @override
  final String wireName = 'NotificationScope';

  @override
  Object serialize(
    Serializers serializers,
    NotificationScope object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  NotificationScope deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => NotificationScope.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
