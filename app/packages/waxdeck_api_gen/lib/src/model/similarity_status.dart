//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'similarity_status.g.dart';

/// Coverage of the sonic-similarity surface.
///
/// Properties:
/// * [enabled] - Whether an analyzer can feed this surface: the server's embedded analyzer is running, or an external worker token is configured. 
/// * [model] - The embedding model the stored vectors carry. Absent before the first ingest. 
/// * [dims] - Stored vector dimensionality. Absent before the first ingest.
/// * [embeddedTracks] - Tracks with a stored embedding.
/// * [totalTracks] - Tracks eligible for analysis.
/// * [coveragePct] - `embeddedTracks` over `totalTracks`, 0 to 100. Clients show sonic affordances when coverage is meaningful. 
/// * [queueDepth] - Tracks awaiting analysis.
/// * [lastIngestAt] - When a worker last posted embeddings. Absent before the first ingest. 
@BuiltValue()
abstract class SimilarityStatus implements Built<SimilarityStatus, SimilarityStatusBuilder> {
  /// Whether an analyzer can feed this surface: the server's embedded analyzer is running, or an external worker token is configured. 
  @BuiltValueField(wireName: r'enabled')
  bool get enabled;

  /// The embedding model the stored vectors carry. Absent before the first ingest. 
  @BuiltValueField(wireName: r'model')
  String? get model;

  /// Stored vector dimensionality. Absent before the first ingest.
  @BuiltValueField(wireName: r'dims')
  int? get dims;

  /// Tracks with a stored embedding.
  @BuiltValueField(wireName: r'embeddedTracks')
  int get embeddedTracks;

  /// Tracks eligible for analysis.
  @BuiltValueField(wireName: r'totalTracks')
  int get totalTracks;

  /// `embeddedTracks` over `totalTracks`, 0 to 100. Clients show sonic affordances when coverage is meaningful. 
  @BuiltValueField(wireName: r'coveragePct')
  num get coveragePct;

  /// Tracks awaiting analysis.
  @BuiltValueField(wireName: r'queueDepth')
  int get queueDepth;

  /// When a worker last posted embeddings. Absent before the first ingest. 
  @BuiltValueField(wireName: r'lastIngestAt')
  DateTime? get lastIngestAt;

  SimilarityStatus._();

  factory SimilarityStatus([void updates(SimilarityStatusBuilder b)]) = _$SimilarityStatus;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SimilarityStatusBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SimilarityStatus> get serializer => _$SimilarityStatusSerializer();
}

class _$SimilarityStatusSerializer implements PrimitiveSerializer<SimilarityStatus> {
  @override
  final Iterable<Type> types = const [SimilarityStatus, _$SimilarityStatus];

  @override
  final String wireName = r'SimilarityStatus';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SimilarityStatus object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'enabled';
    yield serializers.serialize(
      object.enabled,
      specifiedType: const FullType(bool),
    );
    if (object.model != null) {
      yield r'model';
      yield serializers.serialize(
        object.model,
        specifiedType: const FullType(String),
      );
    }
    if (object.dims != null) {
      yield r'dims';
      yield serializers.serialize(
        object.dims,
        specifiedType: const FullType(int),
      );
    }
    yield r'embeddedTracks';
    yield serializers.serialize(
      object.embeddedTracks,
      specifiedType: const FullType(int),
    );
    yield r'totalTracks';
    yield serializers.serialize(
      object.totalTracks,
      specifiedType: const FullType(int),
    );
    yield r'coveragePct';
    yield serializers.serialize(
      object.coveragePct,
      specifiedType: const FullType(num),
    );
    yield r'queueDepth';
    yield serializers.serialize(
      object.queueDepth,
      specifiedType: const FullType(int),
    );
    if (object.lastIngestAt != null) {
      yield r'lastIngestAt';
      yield serializers.serialize(
        object.lastIngestAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SimilarityStatus object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SimilarityStatusBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'enabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.enabled = valueDes;
          break;
        case r'model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.model = valueDes;
          break;
        case r'dims':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.dims = valueDes;
          break;
        case r'embeddedTracks':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.embeddedTracks = valueDes;
          break;
        case r'totalTracks':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalTracks = valueDes;
          break;
        case r'coveragePct':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.coveragePct = valueDes;
          break;
        case r'queueDepth':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.queueDepth = valueDes;
          break;
        case r'lastIngestAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastIngestAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SimilarityStatus deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SimilarityStatusBuilder();
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

