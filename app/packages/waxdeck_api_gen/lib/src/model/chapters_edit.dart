//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/chapter_mark.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'chapters_edit.g.dart';

/// A replacement chapter list.
///
/// Properties:
/// * [chapters] - Ordered, non-overlapping chapters on the book timeline; empty restores the embedded chapters. 
/// * [lock] - Lock the chapters artifact.
/// * [force] - Override an existing lock.
@BuiltValue()
abstract class ChaptersEdit implements Built<ChaptersEdit, ChaptersEditBuilder> {
  /// Ordered, non-overlapping chapters on the book timeline; empty restores the embedded chapters. 
  @BuiltValueField(wireName: r'chapters')
  BuiltList<ChapterMark> get chapters;

  /// Lock the chapters artifact.
  @BuiltValueField(wireName: r'lock')
  bool? get lock;

  /// Override an existing lock.
  @BuiltValueField(wireName: r'force')
  bool? get force;

  ChaptersEdit._();

  factory ChaptersEdit([void updates(ChaptersEditBuilder b)]) = _$ChaptersEdit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ChaptersEditBuilder b) => b
      ..lock = true
      ..force = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<ChaptersEdit> get serializer => _$ChaptersEditSerializer();
}

class _$ChaptersEditSerializer implements PrimitiveSerializer<ChaptersEdit> {
  @override
  final Iterable<Type> types = const [ChaptersEdit, _$ChaptersEdit];

  @override
  final String wireName = r'ChaptersEdit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ChaptersEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'chapters';
    yield serializers.serialize(
      object.chapters,
      specifiedType: const FullType(BuiltList, [FullType(ChapterMark)]),
    );
    if (object.lock != null) {
      yield r'lock';
      yield serializers.serialize(
        object.lock,
        specifiedType: const FullType(bool),
      );
    }
    if (object.force != null) {
      yield r'force';
      yield serializers.serialize(
        object.force,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ChaptersEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ChaptersEditBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'chapters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ChapterMark)]),
          ) as BuiltList<ChapterMark>;
          result.chapters.replace(valueDes);
          break;
        case r'lock':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.lock = valueDes;
          break;
        case r'force':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.force = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ChaptersEdit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ChaptersEditBuilder();
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

