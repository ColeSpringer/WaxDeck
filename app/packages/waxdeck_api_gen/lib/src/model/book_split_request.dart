//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'book_split_request.g.dart';

/// Options for a chapter split.
///
/// Properties:
/// * [keepOriginals] - Keep the source file instead of trashing it.
@BuiltValue()
abstract class BookSplitRequest implements Built<BookSplitRequest, BookSplitRequestBuilder> {
  /// Keep the source file instead of trashing it.
  @BuiltValueField(wireName: r'keepOriginals')
  bool? get keepOriginals;

  BookSplitRequest._();

  factory BookSplitRequest([void updates(BookSplitRequestBuilder b)]) = _$BookSplitRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookSplitRequestBuilder b) => b
      ..keepOriginals = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookSplitRequest> get serializer => _$BookSplitRequestSerializer();
}

class _$BookSplitRequestSerializer implements PrimitiveSerializer<BookSplitRequest> {
  @override
  final Iterable<Type> types = const [BookSplitRequest, _$BookSplitRequest];

  @override
  final String wireName = r'BookSplitRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookSplitRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.keepOriginals != null) {
      yield r'keepOriginals';
      yield serializers.serialize(
        object.keepOriginals,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookSplitRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookSplitRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'keepOriginals':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.keepOriginals = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookSplitRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookSplitRequestBuilder();
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

