//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'book_series_entry.g.dart';

/// One book's place in a series.
///
/// Properties:
/// * [sequence] - What the book's tags call its place in the series (\"2\", \"1.5\", \"II\"). A string because that is what a tag holds, and absent when the tags name the series without a number. 
/// * [book] 
@BuiltValue()
abstract class BookSeriesEntry implements Built<BookSeriesEntry, BookSeriesEntryBuilder> {
  /// What the book's tags call its place in the series (\"2\", \"1.5\", \"II\"). A string because that is what a tag holds, and absent when the tags name the series without a number. 
  @BuiltValueField(wireName: r'sequence')
  String? get sequence;

  @BuiltValueField(wireName: r'book')
  ItemSummary get book;

  BookSeriesEntry._();

  factory BookSeriesEntry([void updates(BookSeriesEntryBuilder b)]) = _$BookSeriesEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookSeriesEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookSeriesEntry> get serializer => _$BookSeriesEntrySerializer();
}

class _$BookSeriesEntrySerializer implements PrimitiveSerializer<BookSeriesEntry> {
  @override
  final Iterable<Type> types = const [BookSeriesEntry, _$BookSeriesEntry];

  @override
  final String wireName = r'BookSeriesEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookSeriesEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.sequence != null) {
      yield r'sequence';
      yield serializers.serialize(
        object.sequence,
        specifiedType: const FullType(String),
      );
    }
    yield r'book';
    yield serializers.serialize(
      object.book,
      specifiedType: const FullType(ItemSummary),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    BookSeriesEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookSeriesEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sequence':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sequence = valueDes;
          break;
        case r'book':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ItemSummary),
          ) as ItemSummary;
          result.book = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookSeriesEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookSeriesEntryBuilder();
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

