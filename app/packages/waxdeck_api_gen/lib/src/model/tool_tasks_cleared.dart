//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'tool_tasks_cleared.g.dart';

/// The result of clearing finished tasks.
///
/// Properties:
/// * [deleted] - How many tasks were deleted.
/// * [kept] - How many finished tasks stayed because what they left in the library could not be settled: a book merge's or split's hidden files that could not be named or removed. Each row's `error` says why. 
@BuiltValue()
abstract class ToolTasksCleared implements Built<ToolTasksCleared, ToolTasksClearedBuilder> {
  /// How many tasks were deleted.
  @BuiltValueField(wireName: r'deleted')
  int get deleted;

  /// How many finished tasks stayed because what they left in the library could not be settled: a book merge's or split's hidden files that could not be named or removed. Each row's `error` says why. 
  @BuiltValueField(wireName: r'kept')
  int get kept;

  ToolTasksCleared._();

  factory ToolTasksCleared([void updates(ToolTasksClearedBuilder b)]) = _$ToolTasksCleared;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ToolTasksClearedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ToolTasksCleared> get serializer => _$ToolTasksClearedSerializer();
}

class _$ToolTasksClearedSerializer implements PrimitiveSerializer<ToolTasksCleared> {
  @override
  final Iterable<Type> types = const [ToolTasksCleared, _$ToolTasksCleared];

  @override
  final String wireName = r'ToolTasksCleared';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ToolTasksCleared object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'deleted';
    yield serializers.serialize(
      object.deleted,
      specifiedType: const FullType(int),
    );
    yield r'kept';
    yield serializers.serialize(
      object.kept,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ToolTasksCleared object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ToolTasksClearedBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'deleted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.deleted = valueDes;
          break;
        case r'kept':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.kept = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ToolTasksCleared deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ToolTasksClearedBuilder();
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


