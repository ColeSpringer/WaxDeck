//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/book_series.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'book_series_page.g.dart';

/// One keyset page of audiobook series.
///
/// Properties:
/// * [series] - Series in collation order.
/// * [nextCursor] - Cursor for the next page; absent on the last one.
@BuiltValue()
abstract class BookSeriesPage implements Built<BookSeriesPage, BookSeriesPageBuilder> {
  /// Series in collation order.
  @BuiltValueField(wireName: r'series')
  BuiltList<BookSeries> get series;

  /// Cursor for the next page; absent on the last one.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  BookSeriesPage._();

  factory BookSeriesPage([void updates(BookSeriesPageBuilder b)]) = _$BookSeriesPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookSeriesPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookSeriesPage> get serializer => _$BookSeriesPageSerializer();
}

class _$BookSeriesPageSerializer implements PrimitiveSerializer<BookSeriesPage> {
  @override
  final Iterable<Type> types = const [BookSeriesPage, _$BookSeriesPage];

  @override
  final String wireName = r'BookSeriesPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookSeriesPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'series';
    yield serializers.serialize(
      object.series,
      specifiedType: const FullType(BuiltList, [FullType(BookSeries)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookSeriesPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookSeriesPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'series':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(BookSeries)]),
          ) as BuiltList<BookSeries>;
          result.series.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextCursor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookSeriesPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookSeriesPageBuilder();
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

