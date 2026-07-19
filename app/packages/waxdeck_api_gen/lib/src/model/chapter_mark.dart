//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'chapter_mark.g.dart';

/// One chapter mark on an item's timeline.
///
/// Properties:
/// * [index] - Zero-based chapter position.
/// * [title] - Chapter title.
/// * [startMs] - Chapter start in milliseconds (book-timeline milliseconds for multi-part audiobooks). 
/// * [endMs] - Chapter end in milliseconds, exclusive. Absent for open-ended final chapters. 
@BuiltValue()
abstract class ChapterMark implements Built<ChapterMark, ChapterMarkBuilder> {
  /// Zero-based chapter position.
  @BuiltValueField(wireName: r'index')
  int get index;

  /// Chapter title.
  @BuiltValueField(wireName: r'title')
  String? get title;

  /// Chapter start in milliseconds (book-timeline milliseconds for multi-part audiobooks). 
  @BuiltValueField(wireName: r'startMs')
  int get startMs;

  /// Chapter end in milliseconds, exclusive. Absent for open-ended final chapters. 
  @BuiltValueField(wireName: r'endMs')
  int? get endMs;

  ChapterMark._();

  factory ChapterMark([void updates(ChapterMarkBuilder b)]) = _$ChapterMark;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ChapterMarkBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ChapterMark> get serializer => _$ChapterMarkSerializer();
}

class _$ChapterMarkSerializer implements PrimitiveSerializer<ChapterMark> {
  @override
  final Iterable<Type> types = const [ChapterMark, _$ChapterMark];

  @override
  final String wireName = r'ChapterMark';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ChapterMark object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'index';
    yield serializers.serialize(
      object.index,
      specifiedType: const FullType(int),
    );
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType(String),
      );
    }
    yield r'startMs';
    yield serializers.serialize(
      object.startMs,
      specifiedType: const FullType(int),
    );
    if (object.endMs != null) {
      yield r'endMs';
      yield serializers.serialize(
        object.endMs,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ChapterMark object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ChapterMarkBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'index':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.index = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'startMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.startMs = valueDes;
          break;
        case r'endMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.endMs = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ChapterMark deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ChapterMarkBuilder();
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

