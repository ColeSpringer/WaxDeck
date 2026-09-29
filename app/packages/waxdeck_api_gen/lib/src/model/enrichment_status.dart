//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/enrichment_phase.dart';
import 'package:waxdeck_api_gen/src/model/enrichment_last_run.dart';
import 'package:waxdeck_api_gen/src/model/enrichment_provider.dart';
import 'package:waxdeck_api_gen/src/model/enrichment_coverage.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_status.g.dart';

/// Enrichment providers and coverage.
///
/// Properties:
/// * [providers] - Every source in the order a pass asks them: the operator's order, then any it does not name, this server's own before the catalog's built-ins. 
/// * [coverage] 
/// * [running] - Whether a whole-library pass is running now.
/// * [runningJob] - The running pass's job pid, when one runs; `GET /jobs/{pid}` follows it more cheaply than this read. 
/// * [configured] - Whether a whole-library pass would do anything: some phase can run, which a switched-on provider gating one or a MusicBrainz contact makes true. Read `phases` for which.  False means every run refuses with `source-unavailable`, so a console should say so rather than offer a button that errors. Distinct from a provider's own `configured`, which is about that provider's key. 
/// * [musicbrainzConfigured] - Whether the MusicBrainz identity phases can run, which needs the `WAXDECK_ENRICHMENT_CONTACT` boot setting. The catalog's built-in sources wait on it too; the provider-gated phases do not. 
/// * [phases] - The phases a run started now would execute; empty exactly when `configured` is false. `identity` and `releases` need the contact; the rest need a source switched on that serves them. 
/// * [lastRun] 
@BuiltValue()
abstract class EnrichmentStatus implements Built<EnrichmentStatus, EnrichmentStatusBuilder> {
  /// Every source in the order a pass asks them: the operator's order, then any it does not name, this server's own before the catalog's built-ins. 
  @BuiltValueField(wireName: r'providers')
  BuiltList<EnrichmentProvider> get providers;

  @BuiltValueField(wireName: r'coverage')
  EnrichmentCoverage get coverage;

  /// Whether a whole-library pass is running now.
  @BuiltValueField(wireName: r'running')
  bool get running;

  /// The running pass's job pid, when one runs; `GET /jobs/{pid}` follows it more cheaply than this read. 
  @BuiltValueField(wireName: r'runningJob')
  String? get runningJob;

  /// Whether a whole-library pass would do anything: some phase can run, which a switched-on provider gating one or a MusicBrainz contact makes true. Read `phases` for which.  False means every run refuses with `source-unavailable`, so a console should say so rather than offer a button that errors. Distinct from a provider's own `configured`, which is about that provider's key. 
  @BuiltValueField(wireName: r'configured')
  bool get configured;

  /// Whether the MusicBrainz identity phases can run, which needs the `WAXDECK_ENRICHMENT_CONTACT` boot setting. The catalog's built-in sources wait on it too; the provider-gated phases do not. 
  @BuiltValueField(wireName: r'musicbrainzConfigured')
  bool get musicbrainzConfigured;

  /// The phases a run started now would execute; empty exactly when `configured` is false. `identity` and `releases` need the contact; the rest need a source switched on that serves them. 
  @BuiltValueField(wireName: r'phases')
  BuiltList<EnrichmentPhase> get phases;

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
    if (object.runningJob != null) {
      yield r'runningJob';
      yield serializers.serialize(
        object.runningJob,
        specifiedType: const FullType(String),
      );
    }
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
      specifiedType: const FullType(BuiltList, [FullType(EnrichmentPhase)]),
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
        case r'runningJob':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.runningJob = valueDes;
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
            specifiedType: const FullType(BuiltList, [FullType(EnrichmentPhase)]),
          ) as BuiltList<EnrichmentPhase>;
          result.phases.replace(valueDes);
          break;
        case r'lastRun':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(EnrichmentLastRun),
          ) as EnrichmentLastRun?;
          if (valueDes == null) continue;
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


