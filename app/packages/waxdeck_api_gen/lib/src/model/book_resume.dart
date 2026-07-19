//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/chapter_mark.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'book_resume.g.dart';

/// The calling user's resume point in one book.
///
/// Properties:
/// * [positionMs] - Book-timeline resume position in milliseconds.
/// * [chapter] 
/// * [updatedAt] - When this position was last written.
@BuiltValue()
abstract class BookResume implements Built<BookResume, BookResumeBuilder> {
  /// Book-timeline resume position in milliseconds.
  @BuiltValueField(wireName: r'positionMs')
  int get positionMs;

  @BuiltValueField(wireName: r'chapter')
  ChapterMark? get chapter;

  /// When this position was last written.
  @BuiltValueField(wireName: r'updatedAt')
  DateTime? get updatedAt;

  BookResume._();

  factory BookResume([void updates(BookResumeBuilder b)]) = _$BookResume;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookResumeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookResume> get serializer => _$BookResumeSerializer();
}

class _$BookResumeSerializer implements PrimitiveSerializer<BookResume> {
  @override
  final Iterable<Type> types = const [BookResume, _$BookResume];

  @override
  final String wireName = r'BookResume';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookResume object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'positionMs';
    yield serializers.serialize(
      object.positionMs,
      specifiedType: const FullType(int),
    );
    if (object.chapter != null) {
      yield r'chapter';
      yield serializers.serialize(
        object.chapter,
        specifiedType: const FullType(ChapterMark),
      );
    }
    if (object.updatedAt != null) {
      yield r'updatedAt';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookResume object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookResumeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'positionMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.positionMs = valueDes;
          break;
        case r'chapter':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ChapterMark),
          ) as ChapterMark;
          result.chapter.replace(valueDes);
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookResume deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookResumeBuilder();
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

