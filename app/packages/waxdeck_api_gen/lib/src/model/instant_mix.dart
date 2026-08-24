//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:waxdeck_api_gen/src/model/mix_basis.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'instant_mix.g.dart';

/// A computed mix. Not persisted; order is play order.
///
/// Properties:
/// * [basis] 
/// * [items] 
/// * [excluded] - How many distinct candidate tracks were dropped because `excludePids` named them. The seed's own drop is not counted. Lets a client tell an empty mix whose candidates are all excluded (\"everything similar is already queued\") apart from a seed with no candidates at all. Absent only from servers predating the field; readers treat that as 0. 
@BuiltValue()
abstract class InstantMix implements Built<InstantMix, InstantMixBuilder> {
  @BuiltValueField(wireName: r'basis')
  MixBasis get basis;
  // enum basisEnum {  sonic,  metadata,  };

  @BuiltValueField(wireName: r'items')
  BuiltList<ItemSummary> get items;

  /// How many distinct candidate tracks were dropped because `excludePids` named them. The seed's own drop is not counted. Lets a client tell an empty mix whose candidates are all excluded (\"everything similar is already queued\") apart from a seed with no candidates at all. Absent only from servers predating the field; readers treat that as 0. 
  @BuiltValueField(wireName: r'excluded')
  int? get excluded;

  InstantMix._();

  factory InstantMix([void updates(InstantMixBuilder b)]) = _$InstantMix;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InstantMixBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InstantMix> get serializer => _$InstantMixSerializer();
}

class _$InstantMixSerializer implements PrimitiveSerializer<InstantMix> {
  @override
  final Iterable<Type> types = const [InstantMix, _$InstantMix];

  @override
  final String wireName = r'InstantMix';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InstantMix object, {
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
    if (object.excluded != null) {
      yield r'excluded';
      yield serializers.serialize(
        object.excluded,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InstantMix object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InstantMixBuilder result,
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
        case r'excluded':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.excluded = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InstantMix deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InstantMixBuilder();
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

