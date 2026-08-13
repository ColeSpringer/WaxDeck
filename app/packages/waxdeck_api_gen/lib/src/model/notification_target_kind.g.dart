// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_target_kind.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const NotificationTargetKind _$pushover = const NotificationTargetKind._(
  'pushover',
);
const NotificationTargetKind _$ntfy = const NotificationTargetKind._('ntfy');
const NotificationTargetKind _$gotify = const NotificationTargetKind._(
  'gotify',
);
const NotificationTargetKind _$discord = const NotificationTargetKind._(
  'discord',
);
const NotificationTargetKind _$webhook = const NotificationTargetKind._(
  'webhook',
);
const NotificationTargetKind _$apprise = const NotificationTargetKind._(
  'apprise',
);
const NotificationTargetKind _$unifiedpush = const NotificationTargetKind._(
  'unifiedpush',
);
const NotificationTargetKind _$unknownDefaultOpenApi =
    const NotificationTargetKind._('unknownDefaultOpenApi');

NotificationTargetKind _$valueOf(String name) {
  switch (name) {
    case 'pushover':
      return _$pushover;
    case 'ntfy':
      return _$ntfy;
    case 'gotify':
      return _$gotify;
    case 'discord':
      return _$discord;
    case 'webhook':
      return _$webhook;
    case 'apprise':
      return _$apprise;
    case 'unifiedpush':
      return _$unifiedpush;
    case 'unknownDefaultOpenApi':
      return _$unknownDefaultOpenApi;
    default:
      return _$unknownDefaultOpenApi;
  }
}

final BuiltSet<NotificationTargetKind> _$values =
    BuiltSet<NotificationTargetKind>(const <NotificationTargetKind>[
      _$pushover,
      _$ntfy,
      _$gotify,
      _$discord,
      _$webhook,
      _$apprise,
      _$unifiedpush,
      _$unknownDefaultOpenApi,
    ]);

class _$NotificationTargetKindMeta {
  const _$NotificationTargetKindMeta();
  NotificationTargetKind get pushover => _$pushover;
  NotificationTargetKind get ntfy => _$ntfy;
  NotificationTargetKind get gotify => _$gotify;
  NotificationTargetKind get discord => _$discord;
  NotificationTargetKind get webhook => _$webhook;
  NotificationTargetKind get apprise => _$apprise;
  NotificationTargetKind get unifiedpush => _$unifiedpush;
  NotificationTargetKind get unknownDefaultOpenApi => _$unknownDefaultOpenApi;
  NotificationTargetKind valueOf(String name) => _$valueOf(name);
  BuiltSet<NotificationTargetKind> get values => _$values;
}

mixin _$NotificationTargetKindMixin {
  // ignore: non_constant_identifier_names
  _$NotificationTargetKindMeta get NotificationTargetKind =>
      const _$NotificationTargetKindMeta();
}

Serializer<NotificationTargetKind> _$notificationTargetKindSerializer =
    _$NotificationTargetKindSerializer();

class _$NotificationTargetKindSerializer
    implements PrimitiveSerializer<NotificationTargetKind> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'pushover': 'pushover',
    'ntfy': 'ntfy',
    'gotify': 'gotify',
    'discord': 'discord',
    'webhook': 'webhook',
    'apprise': 'apprise',
    'unifiedpush': 'unifiedpush',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'pushover': 'pushover',
    'ntfy': 'ntfy',
    'gotify': 'gotify',
    'discord': 'discord',
    'webhook': 'webhook',
    'apprise': 'apprise',
    'unifiedpush': 'unifiedpush',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[NotificationTargetKind];
  @override
  final String wireName = 'NotificationTargetKind';

  @override
  Object serialize(
    Serializers serializers,
    NotificationTargetKind object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  NotificationTargetKind deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => NotificationTargetKind.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
