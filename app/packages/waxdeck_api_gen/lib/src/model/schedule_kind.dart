//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'schedule_kind.g.dart';

class ScheduleKind extends EnumClass {

  /// A schedulable job kind. A shared named schema on purpose (the path parameter and the schedule object both use it): identical inline enums make the Dart generator emit one enum class into two files, which does not compile. 
  @BuiltValueEnumConst(wireName: r'scan')
  static const ScheduleKind scan = _$scan;
  /// A schedulable job kind. A shared named schema on purpose (the path parameter and the schedule object both use it): identical inline enums make the Dart generator emit one enum class into two files, which does not compile. 
  @BuiltValueEnumConst(wireName: r'backup')
  static const ScheduleKind backup = _$backup;
  /// A schedulable job kind. A shared named schema on purpose (the path parameter and the schedule object both use it): identical inline enums make the Dart generator emit one enum class into two files, which does not compile. 
  @BuiltValueEnumConst(wireName: r'prune')
  static const ScheduleKind prune = _$prune;

  static Serializer<ScheduleKind> get serializer => _$scheduleKindSerializer;

  const ScheduleKind._(String name): super(name);

  static BuiltSet<ScheduleKind> get values => _$values;
  static ScheduleKind valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class ScheduleKindMixin = Object with _$ScheduleKindMixin;

