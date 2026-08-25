//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/enrich_field_proposal.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/enrich_cover_proposal.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrich_preview.g.dart';

/// What a one-item enrichment would change, without having changed it. `fields` and `cover` together are the proposal to pass back on `enrichItem`. 
///
/// Properties:
/// * [fields] - The field values providers would fill.
/// * [cover] 
/// * [skipped] - Wants nothing is proposed for, each naming why - the same reasons the blind fetch reports. 
@BuiltValue()
abstract class EnrichPreview implements Built<EnrichPreview, EnrichPreviewBuilder> {
  /// The field values providers would fill.
  @BuiltValueField(wireName: r'fields')
  BuiltList<EnrichFieldProposal> get fields;

  @BuiltValueField(wireName: r'cover')
  EnrichCoverProposal? get cover;

  /// Wants nothing is proposed for, each naming why - the same reasons the blind fetch reports. 
  @BuiltValueField(wireName: r'skipped')
  BuiltList<String> get skipped;

  EnrichPreview._();

  factory EnrichPreview([void updates(EnrichPreviewBuilder b)]) = _$EnrichPreview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichPreviewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichPreview> get serializer => _$EnrichPreviewSerializer();
}

class _$EnrichPreviewSerializer implements PrimitiveSerializer<EnrichPreview> {
  @override
  final Iterable<Type> types = const [EnrichPreview, _$EnrichPreview];

  @override
  final String wireName = r'EnrichPreview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'fields';
    yield serializers.serialize(
      object.fields,
      specifiedType: const FullType(BuiltList, [FullType(EnrichFieldProposal)]),
    );
    if (object.cover != null) {
      yield r'cover';
      yield serializers.serialize(
        object.cover,
        specifiedType: const FullType(EnrichCoverProposal),
      );
    }
    yield r'skipped';
    yield serializers.serialize(
      object.skipped,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichPreviewBuilder result,
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
        case r'skipped':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.skipped.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichPreview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichPreviewBuilder();
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

