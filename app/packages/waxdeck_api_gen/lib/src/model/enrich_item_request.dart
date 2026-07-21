//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrich_item_request.g.dart';

/// What to fetch for one item.
///
/// Properties:
/// * [want] - The artifacts to fetch.
@BuiltValue()
abstract class EnrichItemRequest implements Built<EnrichItemRequest, EnrichItemRequestBuilder> {
  /// The artifacts to fetch.
  @BuiltValueField(wireName: r'want')
  BuiltList<EnrichItemRequestWantEnum> get want;
  // enum wantEnum {  cover,  lyrics,  genres,  book,  };

  EnrichItemRequest._();

  factory EnrichItemRequest([void updates(EnrichItemRequestBuilder b)]) = _$EnrichItemRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichItemRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichItemRequest> get serializer => _$EnrichItemRequestSerializer();
}

class _$EnrichItemRequestSerializer implements PrimitiveSerializer<EnrichItemRequest> {
  @override
  final Iterable<Type> types = const [EnrichItemRequest, _$EnrichItemRequest];

  @override
  final String wireName = r'EnrichItemRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichItemRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'want';
    yield serializers.serialize(
      object.want,
      specifiedType: const FullType(BuiltList, [FullType(EnrichItemRequestWantEnum)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichItemRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichItemRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'want':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EnrichItemRequestWantEnum)]),
          ) as BuiltList<EnrichItemRequestWantEnum>;
          result.want.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichItemRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichItemRequestBuilder();
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

class EnrichItemRequestWantEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'cover')
  static const EnrichItemRequestWantEnum cover = _$enrichItemRequestWantEnum_cover;
  @BuiltValueEnumConst(wireName: r'lyrics')
  static const EnrichItemRequestWantEnum lyrics = _$enrichItemRequestWantEnum_lyrics;
  @BuiltValueEnumConst(wireName: r'genres')
  static const EnrichItemRequestWantEnum genres = _$enrichItemRequestWantEnum_genres;
  @BuiltValueEnumConst(wireName: r'book')
  static const EnrichItemRequestWantEnum book = _$enrichItemRequestWantEnum_book;

  static Serializer<EnrichItemRequestWantEnum> get serializer => _$enrichItemRequestWantEnumSerializer;

  const EnrichItemRequestWantEnum._(String name): super(name);

  static BuiltSet<EnrichItemRequestWantEnum> get values => _$enrichItemRequestWantEnumValues;
  static EnrichItemRequestWantEnum valueOf(String name) => _$enrichItemRequestWantEnumValueOf(name);
}

