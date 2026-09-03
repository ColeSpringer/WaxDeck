//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrich_field_proposal.g.dart';

/// One field an enrichment provider would fill. `lyrics` carries the full text (LRC when the provider answered timed lines); `genre` the joined, normalized genre scalar; a book want proposes each scalar it can fill as its own row.  Every row is fill-when-empty and lock-respecting: enrichment never replaces a value someone else set, which is what makes the injected providers safe to run beside MusicBrainz matching. Matching is authoritative for identity and locks what it writes, so these fill only what nothing has claimed. 
///
/// Properties:
/// * [name] - The metadata field the proposal targets.
/// * [current] - The stored value the proposal would replace. Empty today by construction - enrichment only fills empty fields - but reported so a diff never has to trust that rule. 
/// * [proposed] - The value the provider answered with.
/// * [provider] - The provider that supplied the value.
@BuiltValue()
abstract class EnrichFieldProposal implements Built<EnrichFieldProposal, EnrichFieldProposalBuilder> {
  /// The metadata field the proposal targets.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// The stored value the proposal would replace. Empty today by construction - enrichment only fills empty fields - but reported so a diff never has to trust that rule. 
  @BuiltValueField(wireName: r'current')
  String? get current;

  /// The value the provider answered with.
  @BuiltValueField(wireName: r'proposed')
  String get proposed;

  /// The provider that supplied the value.
  @BuiltValueField(wireName: r'provider')
  String get provider;

  EnrichFieldProposal._();

  factory EnrichFieldProposal([void updates(EnrichFieldProposalBuilder b)]) = _$EnrichFieldProposal;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichFieldProposalBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichFieldProposal> get serializer => _$EnrichFieldProposalSerializer();
}

class _$EnrichFieldProposalSerializer implements PrimitiveSerializer<EnrichFieldProposal> {
  @override
  final Iterable<Type> types = const [EnrichFieldProposal, _$EnrichFieldProposal];

  @override
  final String wireName = r'EnrichFieldProposal';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichFieldProposal object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.current != null) {
      yield r'current';
      yield serializers.serialize(
        object.current,
        specifiedType: const FullType(String),
      );
    }
    yield r'proposed';
    yield serializers.serialize(
      object.proposed,
      specifiedType: const FullType(String),
    );
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichFieldProposal object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichFieldProposalBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'current':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.current = valueDes;
          break;
        case r'proposed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.proposed = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.provider = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichFieldProposal deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichFieldProposalBuilder();
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

