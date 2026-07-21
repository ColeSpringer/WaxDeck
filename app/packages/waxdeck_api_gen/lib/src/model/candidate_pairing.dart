//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'candidate_pairing.g.dart';

/// One proposed file-to-release-track pairing; the side-by-side diff renders current values (via `trackIndex` into the entry's tracks) against these proposed values. 
///
/// Properties:
/// * [trackIndex] - Index into the entry's `tracks`.
/// * [position] - Proposed track number on the release.
/// * [disc] - Proposed disc number.
/// * [title] - Proposed title.
/// * [artist] - Proposed per-track artist, present when it differs from the release artist (compilations). 
/// * [durationMs] - The release track's length, 0 when unknown.
/// * [recordingMbid] - The MusicBrainz recording id this pairing maps to.
/// * [distance] - The pairing's own distance in 0 to 1.
@BuiltValue()
abstract class CandidatePairing implements Built<CandidatePairing, CandidatePairingBuilder> {
  /// Index into the entry's `tracks`.
  @BuiltValueField(wireName: r'trackIndex')
  int get trackIndex;

  /// Proposed track number on the release.
  @BuiltValueField(wireName: r'position')
  int get position;

  /// Proposed disc number.
  @BuiltValueField(wireName: r'disc')
  int? get disc;

  /// Proposed title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Proposed per-track artist, present when it differs from the release artist (compilations). 
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// The release track's length, 0 when unknown.
  @BuiltValueField(wireName: r'durationMs')
  int? get durationMs;

  /// The MusicBrainz recording id this pairing maps to.
  @BuiltValueField(wireName: r'recordingMbid')
  String? get recordingMbid;

  /// The pairing's own distance in 0 to 1.
  @BuiltValueField(wireName: r'distance')
  double get distance;

  CandidatePairing._();

  factory CandidatePairing([void updates(CandidatePairingBuilder b)]) = _$CandidatePairing;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CandidatePairingBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CandidatePairing> get serializer => _$CandidatePairingSerializer();
}

class _$CandidatePairingSerializer implements PrimitiveSerializer<CandidatePairing> {
  @override
  final Iterable<Type> types = const [CandidatePairing, _$CandidatePairing];

  @override
  final String wireName = r'CandidatePairing';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CandidatePairing object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'trackIndex';
    yield serializers.serialize(
      object.trackIndex,
      specifiedType: const FullType(int),
    );
    yield r'position';
    yield serializers.serialize(
      object.position,
      specifiedType: const FullType(int),
    );
    if (object.disc != null) {
      yield r'disc';
      yield serializers.serialize(
        object.disc,
        specifiedType: const FullType(int),
      );
    }
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    if (object.durationMs != null) {
      yield r'durationMs';
      yield serializers.serialize(
        object.durationMs,
        specifiedType: const FullType(int),
      );
    }
    if (object.recordingMbid != null) {
      yield r'recordingMbid';
      yield serializers.serialize(
        object.recordingMbid,
        specifiedType: const FullType(String),
      );
    }
    yield r'distance';
    yield serializers.serialize(
      object.distance,
      specifiedType: const FullType(double),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CandidatePairing object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CandidatePairingBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'trackIndex':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.trackIndex = valueDes;
          break;
        case r'position':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.position = valueDes;
          break;
        case r'disc':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.disc = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'artist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artist = valueDes;
          break;
        case r'durationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMs = valueDes;
          break;
        case r'recordingMbid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.recordingMbid = valueDes;
          break;
        case r'distance':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.distance = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CandidatePairing deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CandidatePairingBuilder();
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

