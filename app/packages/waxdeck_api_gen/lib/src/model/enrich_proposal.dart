//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/enrich_field_proposal.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/enrich_cover_proposal.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrich_proposal.g.dart';

/// A previewed enrichment to commit as approved. Both halves are the preview's own, passed back verbatim; the server writes these values rather than fetching fresh ones. `proposal` on `previewEnrichItem` has no effect. 
///
/// Properties:
/// * [fields] - The approved field proposals.
/// * [cover] 
@BuiltValue()
abstract class EnrichProposal implements Built<EnrichProposal, EnrichProposalBuilder> {
  /// The approved field proposals.
  @BuiltValueField(wireName: r'fields')
  BuiltList<EnrichFieldProposal>? get fields;

  @BuiltValueField(wireName: r'cover')
  EnrichCoverProposal? get cover;

  EnrichProposal._();

  factory EnrichProposal([void updates(EnrichProposalBuilder b)]) = _$EnrichProposal;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichProposalBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichProposal> get serializer => _$EnrichProposalSerializer();
}

class _$EnrichProposalSerializer implements PrimitiveSerializer<EnrichProposal> {
  @override
  final Iterable<Type> types = const [EnrichProposal, _$EnrichProposal];

  @override
  final String wireName = r'EnrichProposal';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichProposal object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.fields != null) {
      yield r'fields';
      yield serializers.serialize(
        object.fields,
        specifiedType: const FullType(BuiltList, [FullType(EnrichFieldProposal)]),
      );
    }
    if (object.cover != null) {
      yield r'cover';
      yield serializers.serialize(
        object.cover,
        specifiedType: const FullType(EnrichCoverProposal),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichProposal object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichProposalBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'fields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EnrichFieldProposal)]),
          ) as BuiltList<EnrichFieldProposal>;
          result.fields.replace(valueDes);
          break;
        case r'cover':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EnrichCoverProposal),
          ) as EnrichCoverProposal;
          result.cover.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichProposal deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichProposalBuilder();
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

