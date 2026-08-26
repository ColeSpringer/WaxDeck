//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'tool_task.g.dart';

/// One background tool task.
///
/// Properties:
/// * [id] - Task pid.
/// * [type] - The operation: `book-merge`, `book-split`, `cue-split`, `acquire`, or `playlist-sync`. A string, not a closed enum. 
/// * [state] - `queued`, `running`, `done`, or `failed`. A string, not a closed enum. 
/// * [itemPid] - The book, track, or playlist the task was started from. 
/// * [progressPct] - Progress in percent when the engine reports it.
/// * [error] - Why the task failed, when `failed`.
/// * [resultPids] - What the task produced once `done`: the merged book or the split pieces (item pids), or the review entries an acquisition or playlist sync opened (entry pids). 
/// * [createdAt] - When the task was queued.
/// * [finishedAt] - When it reached a terminal state.
/// * [summary] - Task-type-specific result detail once the task finishes, for example a migration import's match-and-write report. Shapes are documented per task type and may grow fields. 
@BuiltValue()
abstract class ToolTask implements Built<ToolTask, ToolTaskBuilder> {
  /// Task pid.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// The operation: `book-merge`, `book-split`, `cue-split`, `acquire`, or `playlist-sync`. A string, not a closed enum. 
  @BuiltValueField(wireName: r'type')
  String get type;

  /// `queued`, `running`, `done`, or `failed`. A string, not a closed enum. 
  @BuiltValueField(wireName: r'state')
  String get state;

  /// The book, track, or playlist the task was started from. 
  @BuiltValueField(wireName: r'itemPid')
  String? get itemPid;

  /// Progress in percent when the engine reports it.
  @BuiltValueField(wireName: r'progressPct')
  double? get progressPct;

  /// Why the task failed, when `failed`.
  @BuiltValueField(wireName: r'error')
  String? get error;

  /// What the task produced once `done`: the merged book or the split pieces (item pids), or the review entries an acquisition or playlist sync opened (entry pids). 
  @BuiltValueField(wireName: r'resultPids')
  BuiltList<String>? get resultPids;

  /// When the task was queued.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  /// When it reached a terminal state.
  @BuiltValueField(wireName: r'finishedAt')
  DateTime? get finishedAt;

  /// Task-type-specific result detail once the task finishes, for example a migration import's match-and-write report. Shapes are documented per task type and may grow fields. 
  @BuiltValueField(wireName: r'summary')
  BuiltMap<String, JsonObject?>? get summary;

  ToolTask._();

  factory ToolTask([void updates(ToolTaskBuilder b)]) = _$ToolTask;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ToolTaskBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ToolTask> get serializer => _$ToolTaskSerializer();
}

class _$ToolTaskSerializer implements PrimitiveSerializer<ToolTask> {
  @override
  final Iterable<Type> types = const [ToolTask, _$ToolTask];

  @override
  final String wireName = r'ToolTask';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ToolTask object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    yield r'state';
    yield serializers.serialize(
      object.state,
      specifiedType: const FullType(String),
    );
    if (object.itemPid != null) {
      yield r'itemPid';
      yield serializers.serialize(
        object.itemPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.progressPct != null) {
      yield r'progressPct';
      yield serializers.serialize(
        object.progressPct,
        specifiedType: const FullType(double),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
    if (object.resultPids != null) {
      yield r'resultPids';
      yield serializers.serialize(
        object.resultPids,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.finishedAt != null) {
      yield r'finishedAt';
      yield serializers.serialize(
        object.finishedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.summary != null) {
      yield r'summary';
      yield serializers.serialize(
        object.summary,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ToolTask object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ToolTaskBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.type = valueDes;
          break;
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.state = valueDes;
          break;
        case r'itemPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.itemPid = valueDes;
          break;
        case r'progressPct':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.progressPct = valueDes;
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
        case r'resultPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.resultPids.replace(valueDes);
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'finishedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.finishedAt = valueDes;
          break;
        case r'summary':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
          ) as BuiltMap<String, JsonObject?>;
          result.summary.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ToolTask deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ToolTaskBuilder();
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

