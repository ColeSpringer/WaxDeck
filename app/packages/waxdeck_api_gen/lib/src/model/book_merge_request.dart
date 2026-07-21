//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'book_merge_request.g.dart';

/// Options for a book merge.
///
/// Properties:
/// * [titles] - Chapter titles, one per part in order; absent or empty entries fall back to each part's title tag, then a generated name. A non-empty list must match the part count. 
/// * [keepOriginals] - Keep the source parts instead of trashing them.
@BuiltValue()
abstract class BookMergeRequest implements Built<BookMergeRequest, BookMergeRequestBuilder> {
  /// Chapter titles, one per part in order; absent or empty entries fall back to each part's title tag, then a generated name. A non-empty list must match the part count. 
  @BuiltValueField(wireName: r'titles')
  BuiltList<String>? get titles;

  /// Keep the source parts instead of trashing them.
  @BuiltValueField(wireName: r'keepOriginals')
  bool? get keepOriginals;

  BookMergeRequest._();

  factory BookMergeRequest([void updates(BookMergeRequestBuilder b)]) = _$BookMergeRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookMergeRequestBuilder b) => b
      ..keepOriginals = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookMergeRequest> get serializer => _$BookMergeRequestSerializer();
}

class _$BookMergeRequestSerializer implements PrimitiveSerializer<BookMergeRequest> {
  @override
  final Iterable<Type> types = const [BookMergeRequest, _$BookMergeRequest];

  @override
  final String wireName = r'BookMergeRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookMergeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.titles != null) {
      yield r'titles';
      yield serializers.serialize(
        object.titles,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
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
    BookMergeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookMergeRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'titles':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.titles.replace(valueDes);
          break;
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
  BookMergeRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookMergeRequestBuilder();
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

