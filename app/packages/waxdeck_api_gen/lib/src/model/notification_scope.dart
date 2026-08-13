//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'notification_scope.g.dart';

class NotificationScope extends EnumClass {

  /// Where a notification event or target belongs: `server` is the administrator-managed operations scope, `user` a single user's personal scope. A shared named schema on purpose: identical inline enums make the Dart generator emit one enum class into two files, which does not compile. 
  @BuiltValueEnumConst(wireName: r'server')
  static const NotificationScope server = _$server;
  /// Where a notification event or target belongs: `server` is the administrator-managed operations scope, `user` a single user's personal scope. A shared named schema on purpose: identical inline enums make the Dart generator emit one enum class into two files, which does not compile. 
  @BuiltValueEnumConst(wireName: r'user')
  static const NotificationScope user = _$user;
  /// Where a notification event or target belongs: `server` is the administrator-managed operations scope, `user` a single user's personal scope. A shared named schema on purpose: identical inline enums make the Dart generator emit one enum class into two files, which does not compile. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const NotificationScope unknownDefaultOpenApi = _$unknownDefaultOpenApi;

  static Serializer<NotificationScope> get serializer => _$notificationScopeSerializer;

  const NotificationScope._(String name): super(name);

  static BuiltSet<NotificationScope> get values => _$values;
  static NotificationScope valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class NotificationScopeMixin = Object with _$NotificationScopeMixin;

