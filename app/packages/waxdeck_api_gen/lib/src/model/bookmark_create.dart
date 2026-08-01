//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bookmark_create.g.dart';

/// A new bookmark on the book timeline.
///
/// Properties:
/// * [positionMs] - Book-timeline position in milliseconds.
/// * [note] - An optional note.
@BuiltValue()
abstract class BookmarkCreate implements Built<BookmarkCreate, BookmarkCreateBuilder> {
  /// Book-timeline position in milliseconds.
  @BuiltValueField(wireName: r'positionMs')
  int get positionMs;

  /// An optional note.
  @BuiltValueField(wireName: r'note')
  String? get note;

  BookmarkCreate._();

  factory BookmarkCreate([void updates(BookmarkCreateBuilder b)]) = _$BookmarkCreate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookmarkCreateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookmarkCreate> get serializer => _$BookmarkCreateSerializer();
}

class _$BookmarkCreateSerializer implements PrimitiveSerializer<BookmarkCreate> {
  @override
  final Iterable<Type> types = const [BookmarkCreate, _$BookmarkCreate];

  @override
  final String wireName = r'BookmarkCreate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookmarkCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'positionMs';
    yield serializers.serialize(
      object.positionMs,
      specifiedType: const FullType(int),
    );
    if (object.note != null) {
      yield r'note';
      yield serializers.serialize(
        object.note,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookmarkCreate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookmarkCreateBuilder result,
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
        case r'note':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.note = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookmarkCreate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookmarkCreateBuilder();
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

