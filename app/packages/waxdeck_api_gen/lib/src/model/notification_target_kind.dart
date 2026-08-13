//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_target_kind.g.dart';

class NotificationTargetKind extends EnumClass {

  /// A notification delivery provider. A shared named schema on purpose, like NotificationScope. 
  @BuiltValueEnumConst(wireName: r'pushover')
  static const NotificationTargetKind pushover = _$pushover;
  /// A notification delivery provider. A shared named schema on purpose, like NotificationScope. 
  @BuiltValueEnumConst(wireName: r'ntfy')
  static const NotificationTargetKind ntfy = _$ntfy;
  /// A notification delivery provider. A shared named schema on purpose, like NotificationScope. 
  @BuiltValueEnumConst(wireName: r'gotify')
  static const NotificationTargetKind gotify = _$gotify;
  /// A notification delivery provider. A shared named schema on purpose, like NotificationScope. 
  @BuiltValueEnumConst(wireName: r'discord')
  static const NotificationTargetKind discord = _$discord;
  /// A notification delivery provider. A shared named schema on purpose, like NotificationScope. 
  @BuiltValueEnumConst(wireName: r'webhook')
  static const NotificationTargetKind webhook = _$webhook;
  /// A notification delivery provider. A shared named schema on purpose, like NotificationScope. 
  @BuiltValueEnumConst(wireName: r'apprise')
  static const NotificationTargetKind apprise = _$apprise;
  /// A notification delivery provider. A shared named schema on purpose, like NotificationScope. 
  @BuiltValueEnumConst(wireName: r'unifiedpush')
  static const NotificationTargetKind unifiedpush = _$unifiedpush;
  /// A notification delivery provider. A shared named schema on purpose, like NotificationScope. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const NotificationTargetKind unknownDefaultOpenApi = _$unknownDefaultOpenApi;

  static Serializer<NotificationTargetKind> get serializer => _$notificationTargetKindSerializer;

  const NotificationTargetKind._(String name): super(name);

  static BuiltSet<NotificationTargetKind> get values => _$values;
  static NotificationTargetKind valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class NotificationTargetKindMixin = Object with _$NotificationTargetKindMixin;

