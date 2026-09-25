//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'schedule_kind.g.dart';

/// A schedulable job kind. A shared named schema on purpose (the path parameter and the schedule object both use it): identical inline enums make the Dart generator emit one enum class into two files, which does not compile. `analyze` is off by default and costs a full audio decode per file; see `POST /library/analyze` for what it produces and what it costs. A firing that collides with an analyze pass already running is skipped rather than recorded as run, so it retries on the next tick instead of waiting for the next scheduled window. `enrich` is on by default: the whole-library pass, capped per night (a hand-started run is not), and not forced, so a miss is asked about again only once the retry window has passed. 
class ScheduleKind extends EnumClass {

  @BuiltValueEnumConst(wireName: r'scan')
  static const ScheduleKind scan = _$scan;
  @BuiltValueEnumConst(wireName: r'backup')
  static const ScheduleKind backup = _$backup;
  @BuiltValueEnumConst(wireName: r'prune')
  static const ScheduleKind prune = _$prune;
  @BuiltValueEnumConst(wireName: r'analyze')
  static const ScheduleKind analyze = _$analyze;
  @BuiltValueEnumConst(wireName: r'enrich')
  static const ScheduleKind enrich = _$enrich;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const ScheduleKind unknownDefaultOpenApi = _$unknownDefaultOpenApi;

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

