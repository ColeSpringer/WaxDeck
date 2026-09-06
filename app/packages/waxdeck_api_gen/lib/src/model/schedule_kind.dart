//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'schedule_kind.g.dart';

class ScheduleKind extends EnumClass {

  /// A schedulable job kind. A shared named schema on purpose (the path parameter and the schedule object both use it): identical inline enums make the Dart generator emit one enum class into two files, which does not compile. `analyze` is off by default and costs a full audio decode per file; see `POST /library/analyze` for what it produces and what it costs. A firing that collides with an analyze pass already running is skipped rather than recorded as run, so it retries on the next tick instead of waiting for the next scheduled window. `enrich` is on by default and runs the whole-library enrichment pass, capped per night so a large library's first pass is paid over several nights rather than in one long unattended run; an administrator's own run through `POST /library/enrichment/run` is uncapped. The cap is spent in phase order, so on a server with a MusicBrainz contact the identity phases drain first and the artwork and fields walks wait behind them. It is not forced, so a target some provider already declined is not asked again until a forced run. A firing that collides with a pass already running is skipped the way `analyze` is. 
  @BuiltValueEnumConst(wireName: r'scan')
  static const ScheduleKind scan = _$scan;
  /// A schedulable job kind. A shared named schema on purpose (the path parameter and the schedule object both use it): identical inline enums make the Dart generator emit one enum class into two files, which does not compile. `analyze` is off by default and costs a full audio decode per file; see `POST /library/analyze` for what it produces and what it costs. A firing that collides with an analyze pass already running is skipped rather than recorded as run, so it retries on the next tick instead of waiting for the next scheduled window. `enrich` is on by default and runs the whole-library enrichment pass, capped per night so a large library's first pass is paid over several nights rather than in one long unattended run; an administrator's own run through `POST /library/enrichment/run` is uncapped. The cap is spent in phase order, so on a server with a MusicBrainz contact the identity phases drain first and the artwork and fields walks wait behind them. It is not forced, so a target some provider already declined is not asked again until a forced run. A firing that collides with a pass already running is skipped the way `analyze` is. 
  @BuiltValueEnumConst(wireName: r'backup')
  static const ScheduleKind backup = _$backup;
  /// A schedulable job kind. A shared named schema on purpose (the path parameter and the schedule object both use it): identical inline enums make the Dart generator emit one enum class into two files, which does not compile. `analyze` is off by default and costs a full audio decode per file; see `POST /library/analyze` for what it produces and what it costs. A firing that collides with an analyze pass already running is skipped rather than recorded as run, so it retries on the next tick instead of waiting for the next scheduled window. `enrich` is on by default and runs the whole-library enrichment pass, capped per night so a large library's first pass is paid over several nights rather than in one long unattended run; an administrator's own run through `POST /library/enrichment/run` is uncapped. The cap is spent in phase order, so on a server with a MusicBrainz contact the identity phases drain first and the artwork and fields walks wait behind them. It is not forced, so a target some provider already declined is not asked again until a forced run. A firing that collides with a pass already running is skipped the way `analyze` is. 
  @BuiltValueEnumConst(wireName: r'prune')
  static const ScheduleKind prune = _$prune;
  /// A schedulable job kind. A shared named schema on purpose (the path parameter and the schedule object both use it): identical inline enums make the Dart generator emit one enum class into two files, which does not compile. `analyze` is off by default and costs a full audio decode per file; see `POST /library/analyze` for what it produces and what it costs. A firing that collides with an analyze pass already running is skipped rather than recorded as run, so it retries on the next tick instead of waiting for the next scheduled window. `enrich` is on by default and runs the whole-library enrichment pass, capped per night so a large library's first pass is paid over several nights rather than in one long unattended run; an administrator's own run through `POST /library/enrichment/run` is uncapped. The cap is spent in phase order, so on a server with a MusicBrainz contact the identity phases drain first and the artwork and fields walks wait behind them. It is not forced, so a target some provider already declined is not asked again until a forced run. A firing that collides with a pass already running is skipped the way `analyze` is. 
  @BuiltValueEnumConst(wireName: r'analyze')
  static const ScheduleKind analyze = _$analyze;
  /// A schedulable job kind. A shared named schema on purpose (the path parameter and the schedule object both use it): identical inline enums make the Dart generator emit one enum class into two files, which does not compile. `analyze` is off by default and costs a full audio decode per file; see `POST /library/analyze` for what it produces and what it costs. A firing that collides with an analyze pass already running is skipped rather than recorded as run, so it retries on the next tick instead of waiting for the next scheduled window. `enrich` is on by default and runs the whole-library enrichment pass, capped per night so a large library's first pass is paid over several nights rather than in one long unattended run; an administrator's own run through `POST /library/enrichment/run` is uncapped. The cap is spent in phase order, so on a server with a MusicBrainz contact the identity phases drain first and the artwork and fields walks wait behind them. It is not forced, so a target some provider already declined is not asked again until a forced run. A firing that collides with a pass already running is skipped the way `analyze` is. 
  @BuiltValueEnumConst(wireName: r'enrich')
  static const ScheduleKind enrich = _$enrich;
  /// A schedulable job kind. A shared named schema on purpose (the path parameter and the schedule object both use it): identical inline enums make the Dart generator emit one enum class into two files, which does not compile. `analyze` is off by default and costs a full audio decode per file; see `POST /library/analyze` for what it produces and what it costs. A firing that collides with an analyze pass already running is skipped rather than recorded as run, so it retries on the next tick instead of waiting for the next scheduled window. `enrich` is on by default and runs the whole-library enrichment pass, capped per night so a large library's first pass is paid over several nights rather than in one long unattended run; an administrator's own run through `POST /library/enrichment/run` is uncapped. The cap is spent in phase order, so on a server with a MusicBrainz contact the identity phases drain first and the artwork and fields walks wait behind them. It is not forced, so a target some provider already declined is not asked again until a forced run. A firing that collides with a pass already running is skipped the way `analyze` is. 
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

