//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/book_series_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'book_series_detail.g.dart';

/// One audiobook series and the books in it.
///
/// Properties:
/// * [pid] - Series PID.
/// * [name] - The series name, as the books' tags spell it.
/// * [bookCount] - Books in the series, answered only to an account that can see every library. A restricted account reads the length of `books` instead, which is what it can open. 
/// * [totalDurationMs] - Their combined running time, on `bookCount`'s terms. 
/// * [books] - The books this account can open, in the catalog's sequence order. 
@BuiltValue()
abstract class BookSeriesDetail implements Built<BookSeriesDetail, BookSeriesDetailBuilder> {
  /// Series PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// The series name, as the books' tags spell it.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Books in the series, answered only to an account that can see every library. A restricted account reads the length of `books` instead, which is what it can open. 
  @BuiltValueField(wireName: r'bookCount')
  int? get bookCount;

  /// Their combined running time, on `bookCount`'s terms. 
  @BuiltValueField(wireName: r'totalDurationMs')
  int? get totalDurationMs;

  /// The books this account can open, in the catalog's sequence order. 
  @BuiltValueField(wireName: r'books')
  BuiltList<BookSeriesEntry> get books;

  BookSeriesDetail._();

  factory BookSeriesDetail([void updates(BookSeriesDetailBuilder b)]) = _$BookSeriesDetail;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookSeriesDetailBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookSeriesDetail> get serializer => _$BookSeriesDetailSerializer();
}

class _$BookSeriesDetailSerializer implements PrimitiveSerializer<BookSeriesDetail> {
  @override
  final Iterable<Type> types = const [BookSeriesDetail, _$BookSeriesDetail];

  @override
  final String wireName = r'BookSeriesDetail';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookSeriesDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.bookCount != null) {
      yield r'bookCount';
      yield serializers.serialize(
        object.bookCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.totalDurationMs != null) {
      yield r'totalDurationMs';
      yield serializers.serialize(
        object.totalDurationMs,
        specifiedType: const FullType(int),
      );
    }
    yield r'books';
    yield serializers.serialize(
      object.books,
      specifiedType: const FullType(BuiltList, [FullType(BookSeriesEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    BookSeriesDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookSeriesDetailBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'bookCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bookCount = valueDes;
          break;
        case r'totalDurationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalDurationMs = valueDes;
          break;
        case r'books':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(BookSeriesEntry)]),
          ) as BuiltList<BookSeriesEntry>;
          result.books.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookSeriesDetail deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookSeriesDetailBuilder();
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

