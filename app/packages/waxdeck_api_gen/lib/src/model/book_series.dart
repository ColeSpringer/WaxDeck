//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'book_series.g.dart';

/// One audiobook series.
///
/// Properties:
/// * [pid] - Series PID.
/// * [name] - The series name, as the books' tags spell it.
/// * [bookCount] - Books in the series that this account can see.
/// * [totalDurationMs] - Their combined running time.
@BuiltValue()
abstract class BookSeries implements Built<BookSeries, BookSeriesBuilder> {
  /// Series PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// The series name, as the books' tags spell it.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Books in the series that this account can see.
  @BuiltValueField(wireName: r'bookCount')
  int? get bookCount;

  /// Their combined running time.
  @BuiltValueField(wireName: r'totalDurationMs')
  int? get totalDurationMs;

  BookSeries._();

  factory BookSeries([void updates(BookSeriesBuilder b)]) = _$BookSeries;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookSeriesBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookSeries> get serializer => _$BookSeriesSerializer();
}

class _$BookSeriesSerializer implements PrimitiveSerializer<BookSeries> {
  @override
  final Iterable<Type> types = const [BookSeries, _$BookSeries];

  @override
  final String wireName = r'BookSeries';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookSeries object, {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    BookSeries object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookSeriesBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookSeries deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookSeriesBuilder();
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

