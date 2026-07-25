//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/facet_bucket.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'facet_page.g.dart';

/// One keyset-paginated page of a browse dimension's buckets.
///
/// Properties:
/// * [dimension] - A browse dimension: one of `genre`, `artist`, `album-artist`, `album`, `year`, `kind`, or a custom tag dimension spelled `tag.<KEY>` (for example `tag.MOOD`). The fixed set is stable; which tag dimensions exist depends on the library's tags. Tag keys are case-insensitive and canonicalize to upper case, so `tag.mood` and `tag.MOOD` are one dimension; responses echo the canonical spelling. 
/// * [buckets] 
/// * [nextCursor] - Opaque cursor for the next page. Absent on the last page.
@BuiltValue()
abstract class FacetPage implements Built<FacetPage, FacetPageBuilder> {
  /// A browse dimension: one of `genre`, `artist`, `album-artist`, `album`, `year`, `kind`, or a custom tag dimension spelled `tag.<KEY>` (for example `tag.MOOD`). The fixed set is stable; which tag dimensions exist depends on the library's tags. Tag keys are case-insensitive and canonicalize to upper case, so `tag.mood` and `tag.MOOD` are one dimension; responses echo the canonical spelling. 
  @BuiltValueField(wireName: r'dimension')
  String get dimension;

  @BuiltValueField(wireName: r'buckets')
  BuiltList<FacetBucket> get buckets;

  /// Opaque cursor for the next page. Absent on the last page.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  FacetPage._();

  factory FacetPage([void updates(FacetPageBuilder b)]) = _$FacetPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FacetPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FacetPage> get serializer => _$FacetPageSerializer();
}

class _$FacetPageSerializer implements PrimitiveSerializer<FacetPage> {
  @override
  final Iterable<Type> types = const [FacetPage, _$FacetPage];

  @override
  final String wireName = r'FacetPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FacetPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'dimension';
    yield serializers.serialize(
      object.dimension,
      specifiedType: const FullType(String),
    );
    yield r'buckets';
    yield serializers.serialize(
      object.buckets,
      specifiedType: const FullType(BuiltList, [FullType(FacetBucket)]),
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
    FacetPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FacetPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'dimension':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.dimension = valueDes;
          break;
        case r'buckets':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(FacetBucket)]),
          ) as BuiltList<FacetBucket>;
          result.buckets.replace(valueDes);
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
  FacetPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FacetPageBuilder();
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

