//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/tool_task.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'tool_task_page.g.dart';

/// One page of tool tasks.
///
/// Properties:
/// * [tasks] - Tasks, newest first.
/// * [nextCursor] - Cursor for the next page; omitted on the last.
@BuiltValue()
abstract class ToolTaskPage implements Built<ToolTaskPage, ToolTaskPageBuilder> {
  /// Tasks, newest first.
  @BuiltValueField(wireName: r'tasks')
  BuiltList<ToolTask> get tasks;

  /// Cursor for the next page; omitted on the last.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  ToolTaskPage._();

  factory ToolTaskPage([void updates(ToolTaskPageBuilder b)]) = _$ToolTaskPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ToolTaskPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ToolTaskPage> get serializer => _$ToolTaskPageSerializer();
}

class _$ToolTaskPageSerializer implements PrimitiveSerializer<ToolTaskPage> {
  @override
  final Iterable<Type> types = const [ToolTaskPage, _$ToolTaskPage];

  @override
  final String wireName = r'ToolTaskPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ToolTaskPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'tasks';
    yield serializers.serialize(
      object.tasks,
      specifiedType: const FullType(BuiltList, [FullType(ToolTask)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ToolTaskPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ToolTaskPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'tasks':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ToolTask)]),
          ) as BuiltList<ToolTask>;
          result.tasks.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextCursor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ToolTaskPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ToolTaskPageBuilder();
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

