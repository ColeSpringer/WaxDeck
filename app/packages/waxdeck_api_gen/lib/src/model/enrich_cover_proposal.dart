//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrich_cover_proposal.g.dart';

/// One cover image an enrichment provider would store.
///
/// Properties:
/// * [provider] - The provider that supplied the image.
/// * [data] - The image bytes, base64.
/// * [format] - The image format as the provider read it off the transport; a fallback the bytes beat, kept so the commit stores what the preview held. 
/// * [sourceUrl] - Where the provider fetched the image from.
@BuiltValue()
abstract class EnrichCoverProposal implements Built<EnrichCoverProposal, EnrichCoverProposalBuilder> {
  /// The provider that supplied the image.
  @BuiltValueField(wireName: r'provider')
  String get provider;

  /// The image bytes, base64.
  @BuiltValueField(wireName: r'data')
  String get data;

  /// The image format as the provider read it off the transport; a fallback the bytes beat, kept so the commit stores what the preview held. 
  @BuiltValueField(wireName: r'format')
  String? get format;

  /// Where the provider fetched the image from.
  @BuiltValueField(wireName: r'sourceUrl')
  String? get sourceUrl;

  EnrichCoverProposal._();

  factory EnrichCoverProposal([void updates(EnrichCoverProposalBuilder b)]) = _$EnrichCoverProposal;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichCoverProposalBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichCoverProposal> get serializer => _$EnrichCoverProposalSerializer();
}

class _$EnrichCoverProposalSerializer implements PrimitiveSerializer<EnrichCoverProposal> {
  @override
  final Iterable<Type> types = const [EnrichCoverProposal, _$EnrichCoverProposal];

  @override
  final String wireName = r'EnrichCoverProposal';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichCoverProposal object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(String),
    );
    yield r'data';
    yield serializers.serialize(
      object.data,
      specifiedType: const FullType(String),
    );
    if (object.format != null) {
      yield r'format';
      yield serializers.serialize(
        object.format,
        specifiedType: const FullType(String),
      );
    }
    if (object.sourceUrl != null) {
      yield r'sourceUrl';
      yield serializers.serialize(
        object.sourceUrl,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichCoverProposal object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichCoverProposalBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.provider = valueDes;
          break;
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.data = valueDes;
          break;
        case r'format':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.format = valueDes;
          break;
        case r'sourceUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichCoverProposal deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichCoverProposalBuilder();
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

