//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/bookmark.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bookmark_list.g.dart';

/// The caller's bookmarks in one book.
///
/// Properties:
/// * [bookmarks] - Bookmarks ordered by `positionMs`, earliest first.
@BuiltValue()
abstract class BookmarkList implements Built<BookmarkList, BookmarkListBuilder> {
  /// Bookmarks ordered by `positionMs`, earliest first.
  @BuiltValueField(wireName: r'bookmarks')
  BuiltList<Bookmark> get bookmarks;

  BookmarkList._();

  factory BookmarkList([void updates(BookmarkListBuilder b)]) = _$BookmarkList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookmarkListBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookmarkList> get serializer => _$BookmarkListSerializer();
}

class _$BookmarkListSerializer implements PrimitiveSerializer<BookmarkList> {
  @override
  final Iterable<Type> types = const [BookmarkList, _$BookmarkList];

  @override
  final String wireName = r'BookmarkList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookmarkList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'bookmarks';
    yield serializers.serialize(
      object.bookmarks,
      specifiedType: const FullType(BuiltList, [FullType(Bookmark)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    BookmarkList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookmarkListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'bookmarks':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Bookmark)]),
          ) as BuiltList<Bookmark>;
          result.bookmarks.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookmarkList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookmarkListBuilder();
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

