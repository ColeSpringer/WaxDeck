//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bookmark.g.dart';

/// One place a listener marked in a book.
///
/// Properties:
/// * [id] - Bookmark PID.
/// * [positionMs] - Book-timeline position in milliseconds.
/// * [note] - The listener's note, when they wrote one.
/// * [createdAt] - When the bookmark was made.
@BuiltValue()
abstract class Bookmark implements Built<Bookmark, BookmarkBuilder> {
  /// Bookmark PID.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// Book-timeline position in milliseconds.
  @BuiltValueField(wireName: r'positionMs')
  int get positionMs;

  /// The listener's note, when they wrote one.
  @BuiltValueField(wireName: r'note')
  String? get note;

  /// When the bookmark was made.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  Bookmark._();

  factory Bookmark([void updates(BookmarkBuilder b)]) = _$Bookmark;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookmarkBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Bookmark> get serializer => _$BookmarkSerializer();
}

class _$BookmarkSerializer implements PrimitiveSerializer<Bookmark> {
  @override
  final Iterable<Type> types = const [Bookmark, _$Bookmark];

  @override
  final String wireName = r'Bookmark';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Bookmark object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
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
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Bookmark object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookmarkBuilder result,
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
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Bookmark deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookmarkBuilder();
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

