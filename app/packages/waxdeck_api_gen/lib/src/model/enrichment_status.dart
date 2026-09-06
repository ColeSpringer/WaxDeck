//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/enrichment_last_run.dart';
import 'package:waxdeck_api_gen/src/model/enrichment_provider.dart';
import 'package:waxdeck_api_gen/src/model/enrichment_coverage.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_status.g.dart';

/// Enrichment providers and coverage.
///
/// Properties:
/// * [providers] - Registered providers in priority order (this server's own first, then the catalog's key-free built-ins). 
/// * [coverage] 
/// * [running] - Whether a whole-library pass is running now.
/// * [configured] - Whether a whole-library pass would do anything: some phase can run. That is true on any server carrying a provider that gates a phase of its own, and true on every server with a MusicBrainz contact. Read `phases` for which half.  False means every run refuses with `source-unavailable`, so a console should say so rather than offer a button that errors. Distinct from a provider's own `configured`, which is about that provider's key. 
/// * [musicbrainzConfigured] - Whether the MusicBrainz identity phases can run. They need an identifying contact, which is boot configuration (`-enrichment-contact` / `WAXDECK_ENRICHMENT_CONTACT`) and not a runtime setting, because MusicBrainz requires an identifying agent before anything is sent.  It gates the lyrics phase too, whose built-in provider needs no key but is not dialled without an identifying agent. The phases that answer to registered providers (artwork, fields, book metadata, and lyrics where a provider supplies them) run without it, so a server with no contact still enriches - just not identity. A console that says \"enrichment is off\" on this being false would be wrong about the half that does run. 
/// * [phases] - The phases a run started now would execute, in no particular order. Empty exactly when `configured` is false. `identity` and `releases` need the MusicBrainz contact, and so does `lyrics` unless a registered provider supplies them; the rest need a registered provider advertising the matching capability. 
/// * [lastRun] 
@BuiltValue()
abstract class EnrichmentStatus implements Built<EnrichmentStatus, EnrichmentStatusBuilder> {
  /// Registered providers in priority order (this server's own first, then the catalog's key-free built-ins). 
  @BuiltValueField(wireName: r'providers')
  BuiltList<EnrichmentProvider> get providers;

  @BuiltValueField(wireName: r'coverage')
  EnrichmentCoverage get coverage;

  /// Whether a whole-library pass is running now.
  @BuiltValueField(wireName: r'running')
  bool get running;

  /// Whether a whole-library pass would do anything: some phase can run. That is true on any server carrying a provider that gates a phase of its own, and true on every server with a MusicBrainz contact. Read `phases` for which half.  False means every run refuses with `source-unavailable`, so a console should say so rather than offer a button that errors. Distinct from a provider's own `configured`, which is about that provider's key. 
  @BuiltValueField(wireName: r'configured')
  bool get configured;

  /// Whether the MusicBrainz identity phases can run. They need an identifying contact, which is boot configuration (`-enrichment-contact` / `WAXDECK_ENRICHMENT_CONTACT`) and not a runtime setting, because MusicBrainz requires an identifying agent before anything is sent.  It gates the lyrics phase too, whose built-in provider needs no key but is not dialled without an identifying agent. The phases that answer to registered providers (artwork, fields, book metadata, and lyrics where a provider supplies them) run without it, so a server with no contact still enriches - just not identity. A console that says \"enrichment is off\" on this being false would be wrong about the half that does run. 
  @BuiltValueField(wireName: r'musicbrainzConfigured')
  bool get musicbrainzConfigured;

  /// The phases a run started now would execute, in no particular order. Empty exactly when `configured` is false. `identity` and `releases` need the MusicBrainz contact, and so does `lyrics` unless a registered provider supplies them; the rest need a registered provider advertising the matching capability. 
  @BuiltValueField(wireName: r'phases')
  BuiltList<EnrichmentStatusPhasesEnum> get phases;
  // enum phasesEnum {  identity,  releases,  aux-art,  artist-art,  lyrics,  track-fields,  book-fields,  album-fields,  };

  @BuiltValueField(wireName: r'lastRun')
  EnrichmentLastRun? get lastRun;

  EnrichmentStatus._();

  factory EnrichmentStatus([void updates(EnrichmentStatusBuilder b)]) = _$EnrichmentStatus;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentStatusBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentStatus> get serializer => _$EnrichmentStatusSerializer();
}

class _$EnrichmentStatusSerializer implements PrimitiveSerializer<EnrichmentStatus> {
  @override
  final Iterable<Type> types = const [EnrichmentStatus, _$EnrichmentStatus];

  @override
  final String wireName = r'EnrichmentStatus';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentStatus object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'providers';
    yield serializers.serialize(
      object.providers,
      specifiedType: const FullType(BuiltList, [FullType(EnrichmentProvider)]),
    );
    yield r'coverage';
    yield serializers.serialize(
      object.coverage,
      specifiedType: const FullType(EnrichmentCoverage),
    );
    yield r'running';
    yield serializers.serialize(
      object.running,
      specifiedType: const FullType(bool),
    );
    yield r'configured';
    yield serializers.serialize(
      object.configured,
      specifiedType: const FullType(bool),
    );
    yield r'musicbrainzConfigured';
    yield serializers.serialize(
      object.musicbrainzConfigured,
      specifiedType: const FullType(bool),
    );
    yield r'phases';
    yield serializers.serialize(
      object.phases,
      specifiedType: const FullType(BuiltList, [FullType(EnrichmentStatusPhasesEnum)]),
    );
    if (object.lastRun != null) {
      yield r'lastRun';
      yield serializers.serialize(
        object.lastRun,
        specifiedType: const FullType(EnrichmentLastRun),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentStatus object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentStatusBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'providers':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EnrichmentProvider)]),
          ) as BuiltList<EnrichmentProvider>;
          result.providers.replace(valueDes);
          break;
        case r'coverage':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EnrichmentCoverage),
          ) as EnrichmentCoverage;
          result.coverage.replace(valueDes);
          break;
        case r'running':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.running = valueDes;
          break;
        case r'configured':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.configured = valueDes;
          break;
        case r'musicbrainzConfigured':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.musicbrainzConfigured = valueDes;
          break;
        case r'phases':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EnrichmentStatusPhasesEnum)]),
          ) as BuiltList<EnrichmentStatusPhasesEnum>;
          result.phases.replace(valueDes);
          break;
        case r'lastRun':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EnrichmentLastRun),
          ) as EnrichmentLastRun;
          result.lastRun.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentStatus deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentStatusBuilder();
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

class EnrichmentStatusPhasesEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'identity')
  static const EnrichmentStatusPhasesEnum identity = _$enrichmentStatusPhasesEnum_identity;
  @BuiltValueEnumConst(wireName: r'releases')
  static const EnrichmentStatusPhasesEnum releases = _$enrichmentStatusPhasesEnum_releases;
  @BuiltValueEnumConst(wireName: r'aux-art')
  static const EnrichmentStatusPhasesEnum auxArt = _$enrichmentStatusPhasesEnum_auxArt;
  @BuiltValueEnumConst(wireName: r'artist-art')
  static const EnrichmentStatusPhasesEnum artistArt = _$enrichmentStatusPhasesEnum_artistArt;
  @BuiltValueEnumConst(wireName: r'lyrics')
  static const EnrichmentStatusPhasesEnum lyrics = _$enrichmentStatusPhasesEnum_lyrics;
  @BuiltValueEnumConst(wireName: r'track-fields')
  static const EnrichmentStatusPhasesEnum trackFields = _$enrichmentStatusPhasesEnum_trackFields;
  @BuiltValueEnumConst(wireName: r'book-fields')
  static const EnrichmentStatusPhasesEnum bookFields = _$enrichmentStatusPhasesEnum_bookFields;
  @BuiltValueEnumConst(wireName: r'album-fields')
  static const EnrichmentStatusPhasesEnum albumFields = _$enrichmentStatusPhasesEnum_albumFields;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const EnrichmentStatusPhasesEnum unknownDefaultOpenApi = _$enrichmentStatusPhasesEnum_unknownDefaultOpenApi;

  static Serializer<EnrichmentStatusPhasesEnum> get serializer => _$enrichmentStatusPhasesEnumSerializer;

  const EnrichmentStatusPhasesEnum._(String name): super(name);

  static BuiltSet<EnrichmentStatusPhasesEnum> get values => _$enrichmentStatusPhasesEnumValues;
  static EnrichmentStatusPhasesEnum valueOf(String name) => _$enrichmentStatusPhasesEnumValueOf(name);
}

