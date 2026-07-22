//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:waxdeck_api_gen/src/model/mix_basis.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'similar_tracks.g.dart';

/// Tracks similar to a seed, most similar first.
///
/// Properties:
/// * [basis] 
/// * [items] 
@BuiltValue()
abstract class SimilarTracks implements Built<SimilarTracks, SimilarTracksBuilder> {
  @BuiltValueField(wireName: r'basis')
  MixBasis get basis;
  // enum basisEnum {  sonic,  metadata,  };

  @BuiltValueField(wireName: r'items')
  BuiltList<ItemSummary> get items;

  SimilarTracks._();

  factory SimilarTracks([void updates(SimilarTracksBuilder b)]) = _$SimilarTracks;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SimilarTracksBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SimilarTracks> get serializer => _$SimilarTracksSerializer();
}

class _$SimilarTracksSerializer implements PrimitiveSerializer<SimilarTracks> {
  @override
  final Iterable<Type> types = const [SimilarTracks, _$SimilarTracks];

  @override
  final String wireName = r'SimilarTracks';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SimilarTracks object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'basis';
    yield serializers.serialize(
      object.basis,
      specifiedType: const FullType(MixBasis),
    );
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(ItemSummary)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SimilarTracks object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SimilarTracksBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'basis':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MixBasis),
          ) as MixBasis;
          result.basis = valueDes;
          break;
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ItemSummary)]),
          ) as BuiltList<ItemSummary>;
          result.items.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SimilarTracks deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SimilarTracksBuilder();
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

