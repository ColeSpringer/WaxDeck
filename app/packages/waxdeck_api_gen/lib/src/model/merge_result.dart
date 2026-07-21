//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'merge_result.g.dart';

/// The merge outcome.
///
/// Properties:
/// * [merged] - Losers merged.
/// * [childrenMoved] - Children re-parented onto the survivor.
@BuiltValue()
abstract class MergeResult implements Built<MergeResult, MergeResultBuilder> {
  /// Losers merged.
  @BuiltValueField(wireName: r'merged')
  int get merged;

  /// Children re-parented onto the survivor.
  @BuiltValueField(wireName: r'childrenMoved')
  int get childrenMoved;

  MergeResult._();

  factory MergeResult([void updates(MergeResultBuilder b)]) = _$MergeResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MergeResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MergeResult> get serializer => _$MergeResultSerializer();
}

class _$MergeResultSerializer implements PrimitiveSerializer<MergeResult> {
  @override
  final Iterable<Type> types = const [MergeResult, _$MergeResult];

  @override
  final String wireName = r'MergeResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MergeResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'merged';
    yield serializers.serialize(
      object.merged,
      specifiedType: const FullType(int),
    );
    yield r'childrenMoved';
    yield serializers.serialize(
      object.childrenMoved,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MergeResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MergeResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'merged':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.merged = valueDes;
          break;
        case r'childrenMoved':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.childrenMoved = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MergeResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MergeResultBuilder();
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

