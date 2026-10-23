//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_batch.g.dart';

/// One organize run, or an undo of one, and what its moves came to.
///
/// Properties:
/// * [jobPid] - The run's catalog job.
/// * [kind] - An `organize` run, or an `organize-undo` of one.
/// * [state] - The job's state, as `/jobs` reports it; clients treat an unknown value as not finished. 
/// * [startedAt] - When the run started.
/// * [profile] - The profile the run laid out by: the one named, or the library's own when the run planned one managed library. Absent for an undo and for a run that laid several libraries out by their own. 
/// * [committed] - Files the run moved.
/// * [rolledBack] - Moves that failed on disk, leaving the file where it was.
/// * [planned] - Moves a crash left between the disk and the catalog, which the next start settles. 
/// * [undoable] - Whether `/organize/undo` takes the run now.
@BuiltValue()
abstract class OrganizeBatch implements Built<OrganizeBatch, OrganizeBatchBuilder> {
  /// The run's catalog job.
  @BuiltValueField(wireName: r'jobPid')
  String get jobPid;

  /// An `organize` run, or an `organize-undo` of one.
  @BuiltValueField(wireName: r'kind')
  OrganizeBatchKindEnum get kind;
  // enum kindEnum {  organize,  organize-undo,  };

  /// The job's state, as `/jobs` reports it; clients treat an unknown value as not finished. 
  @BuiltValueField(wireName: r'state')
  String get state;

  /// When the run started.
  @BuiltValueField(wireName: r'startedAt')
  DateTime get startedAt;

  /// The profile the run laid out by: the one named, or the library's own when the run planned one managed library. Absent for an undo and for a run that laid several libraries out by their own. 
  @BuiltValueField(wireName: r'profile')
  String? get profile;

  /// Files the run moved.
  @BuiltValueField(wireName: r'committed')
  int get committed;

  /// Moves that failed on disk, leaving the file where it was.
  @BuiltValueField(wireName: r'rolledBack')
  int get rolledBack;

  /// Moves a crash left between the disk and the catalog, which the next start settles. 
  @BuiltValueField(wireName: r'planned')
  int get planned;

  /// Whether `/organize/undo` takes the run now.
  @BuiltValueField(wireName: r'undoable')
  bool get undoable;

  OrganizeBatch._();

  factory OrganizeBatch([void updates(OrganizeBatchBuilder b)]) = _$OrganizeBatch;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeBatchBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeBatch> get serializer => _$OrganizeBatchSerializer();
}

class _$OrganizeBatchSerializer implements PrimitiveSerializer<OrganizeBatch> {
  @override
  final Iterable<Type> types = const [OrganizeBatch, _$OrganizeBatch];

  @override
  final String wireName = r'OrganizeBatch';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeBatch object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'jobPid';
    yield serializers.serialize(
      object.jobPid,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(OrganizeBatchKindEnum),
    );
    yield r'state';
    yield serializers.serialize(
      object.state,
      specifiedType: const FullType(String),
    );
    yield r'startedAt';
    yield serializers.serialize(
      object.startedAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.profile != null) {
      yield r'profile';
      yield serializers.serialize(
        object.profile,
        specifiedType: const FullType(String),
      );
    }
    yield r'committed';
    yield serializers.serialize(
      object.committed,
      specifiedType: const FullType(int),
    );
    yield r'rolledBack';
    yield serializers.serialize(
      object.rolledBack,
      specifiedType: const FullType(int),
    );
    yield r'planned';
    yield serializers.serialize(
      object.planned,
      specifiedType: const FullType(int),
    );
    yield r'undoable';
    yield serializers.serialize(
      object.undoable,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OrganizeBatch object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeBatchBuilder result,
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
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(OrganizeBatchKindEnum),
          ) as OrganizeBatchKindEnum;
          result.kind = valueDes;
          break;
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.state = valueDes;
          break;
        case r'startedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startedAt = valueDes;
          break;
        case r'profile':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.profile = valueDes;
          break;
        case r'committed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.committed = valueDes;
          break;
        case r'rolledBack':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.rolledBack = valueDes;
          break;
        case r'planned':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.planned = valueDes;
          break;
        case r'undoable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.undoable = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrganizeBatch deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeBatchBuilder();
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


/// An `organize` run, or an `organize-undo` of one.
class OrganizeBatchKindEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'organize')
  static const OrganizeBatchKindEnum organize = _$organizeBatchKindEnum_organize;
  @BuiltValueEnumConst(wireName: r'organize-undo')
  static const OrganizeBatchKindEnum organizeUndo = _$organizeBatchKindEnum_organizeUndo;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const OrganizeBatchKindEnum unknownDefaultOpenApi = _$organizeBatchKindEnum_unknownDefaultOpenApi;

  static Serializer<OrganizeBatchKindEnum> get serializer => _$organizeBatchKindEnumSerializer;

  const OrganizeBatchKindEnum._(String name): super(name);

  static BuiltSet<OrganizeBatchKindEnum> get values => _$organizeBatchKindEnumValues;
  static OrganizeBatchKindEnum valueOf(String name) => _$organizeBatchKindEnumValueOf(name);
}

