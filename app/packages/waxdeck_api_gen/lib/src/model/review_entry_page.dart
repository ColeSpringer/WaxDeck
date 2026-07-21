//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/review_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_entry_page.g.dart';

/// One page of review entries.
///
/// Properties:
/// * [entries] - Entries, newest first.
/// * [nextCursor] - Cursor for the next page; omitted on the last.
@BuiltValue()
abstract class ReviewEntryPage implements Built<ReviewEntryPage, ReviewEntryPageBuilder> {
  /// Entries, newest first.
  @BuiltValueField(wireName: r'entries')
  BuiltList<ReviewEntry> get entries;

  /// Cursor for the next page; omitted on the last.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  ReviewEntryPage._();

  factory ReviewEntryPage([void updates(ReviewEntryPageBuilder b)]) = _$ReviewEntryPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewEntryPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewEntryPage> get serializer => _$ReviewEntryPageSerializer();
}

class _$ReviewEntryPageSerializer implements PrimitiveSerializer<ReviewEntryPage> {
  @override
  final Iterable<Type> types = const [ReviewEntryPage, _$ReviewEntryPage];

  @override
  final String wireName = r'ReviewEntryPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewEntryPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(ReviewEntry)]),
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
    ReviewEntryPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewEntryPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ReviewEntry)]),
          ) as BuiltList<ReviewEntry>;
          result.entries.replace(valueDes);
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
  ReviewEntryPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewEntryPageBuilder();
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

