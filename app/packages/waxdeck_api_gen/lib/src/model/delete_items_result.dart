//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/delete_plan_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'delete_items_result.g.dart';

/// What a deletion did, or would do.
///
/// Properties:
/// * [applied] - False for a dry run.
/// * [mode] - The mode that was (or would be) used.
/// * [entries] - Per-item breakdown.
/// * [warnings] - What the deletion did beside removing files, in sentences: a copy that took a deleted file's place, and a file it could not remove, which stayed and is not counted in `entries`. A whole-item delete names each under its item's name. Absent when there is nothing to say. 
/// * [trashed] - Files moved to the trash. Absent from a plan.
/// * [deleted] - Files deleted outright, in `permanent` mode. Absent from a plan. 
/// * [failed] - Files the deletion tried to remove and could not, which stayed where they were; `entries` say whose. Absent from a plan. 
/// * [dirsPruned] - Folders the deletion emptied and removed. Absent from a plan. 
/// * [reclaimedBytes] - Disk space the deletion freed: the files a `permanent` deletion removed. A move to the trash frees nothing until the trash is emptied. Absent from a plan. 
@BuiltValue()
abstract class DeleteItemsResult implements Built<DeleteItemsResult, DeleteItemsResultBuilder> {
  /// False for a dry run.
  @BuiltValueField(wireName: r'applied')
  bool get applied;

  /// The mode that was (or would be) used.
  @BuiltValueField(wireName: r'mode')
  String get mode;

  /// Per-item breakdown.
  @BuiltValueField(wireName: r'entries')
  BuiltList<DeletePlanEntry> get entries;

  /// What the deletion did beside removing files, in sentences: a copy that took a deleted file's place, and a file it could not remove, which stayed and is not counted in `entries`. A whole-item delete names each under its item's name. Absent when there is nothing to say. 
  @BuiltValueField(wireName: r'warnings')
  BuiltList<String>? get warnings;

  /// Files moved to the trash. Absent from a plan.
  @BuiltValueField(wireName: r'trashed')
  int? get trashed;

  /// Files deleted outright, in `permanent` mode. Absent from a plan. 
  @BuiltValueField(wireName: r'deleted')
  int? get deleted;

  /// Files the deletion tried to remove and could not, which stayed where they were; `entries` say whose. Absent from a plan. 
  @BuiltValueField(wireName: r'failed')
  int? get failed;

  /// Folders the deletion emptied and removed. Absent from a plan. 
  @BuiltValueField(wireName: r'dirsPruned')
  int? get dirsPruned;

  /// Disk space the deletion freed: the files a `permanent` deletion removed. A move to the trash frees nothing until the trash is emptied. Absent from a plan. 
  @BuiltValueField(wireName: r'reclaimedBytes')
  int? get reclaimedBytes;

  DeleteItemsResult._();

  factory DeleteItemsResult([void updates(DeleteItemsResultBuilder b)]) = _$DeleteItemsResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeleteItemsResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeleteItemsResult> get serializer => _$DeleteItemsResultSerializer();
}

class _$DeleteItemsResultSerializer implements PrimitiveSerializer<DeleteItemsResult> {
  @override
  final Iterable<Type> types = const [DeleteItemsResult, _$DeleteItemsResult];

  @override
  final String wireName = r'DeleteItemsResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeleteItemsResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'applied';
    yield serializers.serialize(
      object.applied,
      specifiedType: const FullType(bool),
    );
    yield r'mode';
    yield serializers.serialize(
      object.mode,
      specifiedType: const FullType(String),
    );
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(DeletePlanEntry)]),
    );
    if (object.warnings != null) {
      yield r'warnings';
      yield serializers.serialize(
        object.warnings,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.trashed != null) {
      yield r'trashed';
      yield serializers.serialize(
        object.trashed,
        specifiedType: const FullType(int),
      );
    }
    if (object.deleted != null) {
      yield r'deleted';
      yield serializers.serialize(
        object.deleted,
        specifiedType: const FullType(int),
      );
    }
    if (object.failed != null) {
      yield r'failed';
      yield serializers.serialize(
        object.failed,
        specifiedType: const FullType(int),
      );
    }
    if (object.dirsPruned != null) {
      yield r'dirsPruned';
      yield serializers.serialize(
        object.dirsPruned,
        specifiedType: const FullType(int),
      );
    }
    if (object.reclaimedBytes != null) {
      yield r'reclaimedBytes';
      yield serializers.serialize(
        object.reclaimedBytes,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DeleteItemsResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeleteItemsResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'applied':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.applied = valueDes;
          break;
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mode = valueDes;
          break;
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DeletePlanEntry)]),
          ) as BuiltList<DeletePlanEntry>;
          result.entries.replace(valueDes);
          break;
        case r'warnings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.warnings.replace(valueDes);
          break;
        case r'trashed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.trashed = valueDes;
          break;
        case r'deleted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.deleted = valueDes;
          break;
        case r'failed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.failed = valueDes;
          break;
        case r'dirsPruned':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.dirsPruned = valueDes;
          break;
        case r'reclaimedBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.reclaimedBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DeleteItemsResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeleteItemsResultBuilder();
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


