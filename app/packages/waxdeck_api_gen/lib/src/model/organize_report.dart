//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/organize_hold.dart';
import 'package:waxdeck_api_gen/src/model/organize_failure.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_report.g.dart';

/// The outcome of an applied organize pass.
///
/// Properties:
/// * [jobPid] - The catalog job the pass ran as, which `/organize/undo` takes; empty when nothing was left to move and no job ran. 
/// * [moved] - Files moved.
/// * [skipped] - Files already in place.
/// * [held] - Files held back where they are, for any of the causes a plan's `held` counts, `read-only` here being a library made read-only after the plan. 
/// * [holds] - The first five hundred moves held back.
/// * [readOnlyLibraries] - Managed libraries left alone because they are read-only.
/// * [failed] - Files that could not move.
/// * [failures] - The failures, path and reason each.
/// * [dirsPruned] - Folders the moves emptied and removed.
@BuiltValue()
abstract class OrganizeReport implements Built<OrganizeReport, OrganizeReportBuilder> {
  /// The catalog job the pass ran as, which `/organize/undo` takes; empty when nothing was left to move and no job ran. 
  @BuiltValueField(wireName: r'jobPid')
  String get jobPid;

  /// Files moved.
  @BuiltValueField(wireName: r'moved')
  int get moved;

  /// Files already in place.
  @BuiltValueField(wireName: r'skipped')
  int get skipped;

  /// Files held back where they are, for any of the causes a plan's `held` counts, `read-only` here being a library made read-only after the plan. 
  @BuiltValueField(wireName: r'held')
  int get held;

  /// The first five hundred moves held back.
  @BuiltValueField(wireName: r'holds')
  BuiltList<OrganizeHold>? get holds;

  /// Managed libraries left alone because they are read-only.
  @BuiltValueField(wireName: r'readOnlyLibraries')
  int get readOnlyLibraries;

  /// Files that could not move.
  @BuiltValueField(wireName: r'failed')
  int get failed;

  /// The failures, path and reason each.
  @BuiltValueField(wireName: r'failures')
  BuiltList<OrganizeFailure>? get failures;

  /// Folders the moves emptied and removed.
  @BuiltValueField(wireName: r'dirsPruned')
  int? get dirsPruned;

  OrganizeReport._();

  factory OrganizeReport([void updates(OrganizeReportBuilder b)]) = _$OrganizeReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeReport> get serializer => _$OrganizeReportSerializer();
}

class _$OrganizeReportSerializer implements PrimitiveSerializer<OrganizeReport> {
  @override
  final Iterable<Type> types = const [OrganizeReport, _$OrganizeReport];

  @override
  final String wireName = r'OrganizeReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'jobPid';
    yield serializers.serialize(
      object.jobPid,
      specifiedType: const FullType(String),
    );
    yield r'moved';
    yield serializers.serialize(
      object.moved,
      specifiedType: const FullType(int),
    );
    yield r'skipped';
    yield serializers.serialize(
      object.skipped,
      specifiedType: const FullType(int),
    );
    yield r'held';
    yield serializers.serialize(
      object.held,
      specifiedType: const FullType(int),
    );
    if (object.holds != null) {
      yield r'holds';
      yield serializers.serialize(
        object.holds,
        specifiedType: const FullType(BuiltList, [FullType(OrganizeHold)]),
      );
    }
    yield r'readOnlyLibraries';
    yield serializers.serialize(
      object.readOnlyLibraries,
      specifiedType: const FullType(int),
    );
    yield r'failed';
    yield serializers.serialize(
      object.failed,
      specifiedType: const FullType(int),
    );
    if (object.failures != null) {
      yield r'failures';
      yield serializers.serialize(
        object.failures,
        specifiedType: const FullType(BuiltList, [FullType(OrganizeFailure)]),
      );
    }
    if (object.dirsPruned != null) {
      yield r'dirsPruned';
      yield serializers.serialize(
        object.dirsPruned,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OrganizeReport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeReportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'jobPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.jobPid = valueDes;
          break;
        case r'moved':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.moved = valueDes;
          break;
        case r'skipped':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.skipped = valueDes;
          break;
        case r'held':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.held = valueDes;
          break;
        case r'holds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(OrganizeHold)]),
          ) as BuiltList<OrganizeHold>?;
          if (valueDes == null) continue;
          result.holds.replace(valueDes);
          break;
        case r'readOnlyLibraries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.readOnlyLibraries = valueDes;
          break;
        case r'failed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.failed = valueDes;
          break;
        case r'failures':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(OrganizeFailure)]),
          ) as BuiltList<OrganizeFailure>?;
          if (valueDes == null) continue;
          result.failures.replace(valueDes);
          break;
        case r'dirsPruned':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.dirsPruned = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrganizeReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeReportBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}


