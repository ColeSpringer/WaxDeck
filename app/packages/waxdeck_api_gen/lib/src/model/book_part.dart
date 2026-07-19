//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'book_part.g.dart';

/// One backing file of an audiobook, in reading order. `index` is the join key across the whole surface: it matches play-info's `partIndex`, the skip-map `partIndex`, and the same position in download-info's `files` array. 
///
/// Properties:
/// * [index] - Zero-based reading-order position.
/// * [startMs] - Book-timeline millisecond offset where this part begins.
/// * [durationMs] - Part duration in milliseconds.
/// * [displayName] - Human-readable part name (the file's base name).
@BuiltValue()
abstract class BookPart implements Built<BookPart, BookPartBuilder> {
  /// Zero-based reading-order position.
  @BuiltValueField(wireName: r'index')
  int get index;

  /// Book-timeline millisecond offset where this part begins.
  @BuiltValueField(wireName: r'startMs')
  int get startMs;

  /// Part duration in milliseconds.
  @BuiltValueField(wireName: r'durationMs')
  int get durationMs;

  /// Human-readable part name (the file's base name).
  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  BookPart._();

  factory BookPart([void updates(BookPartBuilder b)]) = _$BookPart;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookPartBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookPart> get serializer => _$BookPartSerializer();
}

class _$BookPartSerializer implements PrimitiveSerializer<BookPart> {
  @override
  final Iterable<Type> types = const [BookPart, _$BookPart];

  @override
  final String wireName = r'BookPart';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookPart object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'index';
    yield serializers.serialize(
      object.index,
      specifiedType: const FullType(int),
    );
    yield r'startMs';
    yield serializers.serialize(
      object.startMs,
      specifiedType: const FullType(int),
    );
    yield r'durationMs';
    yield serializers.serialize(
      object.durationMs,
      specifiedType: const FullType(int),
    );
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookPart object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookPartBuilder result,
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
        case r'startMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.startMs = valueDes;
          break;
        case r'durationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMs = valueDes;
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookPart deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookPartBuilder();
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

