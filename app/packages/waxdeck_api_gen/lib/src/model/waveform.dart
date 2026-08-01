//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'waveform.g.dart';

/// One item's amplitude envelope, produced by the catalog's analyze pass and read back unchanged. Nothing here is computed on demand. 
///
/// Properties:
/// * [state] - `ready` (peaks present), `pending` (analyzable, not yet analyzed), or `unavailable` (there will never be a waveform for this item). Open set; treat unknown values as `unavailable`. 
/// * [partIndex] - The described part of a multi-file audiobook. Present only for multi-file books. 
/// * [peaks] - One amplitude per bucket in playback order, `0` silence and `255` full scale (`ready` only). Downsample to the pixel width being drawn. 
/// * [resolution] - How many buckets `peaks` carries (`ready` only). Fixed by the catalog at 1000 today; read it rather than assuming, because an analysis version bump may change it. 
/// * [essenceHash] - Content hash of the analyzed audio essence, matching the download surface's `essenceHash`. A stored waveform whose hash no longer matches the stored audio is stale. 
@BuiltValue()
abstract class Waveform implements Built<Waveform, WaveformBuilder> {
  /// `ready` (peaks present), `pending` (analyzable, not yet analyzed), or `unavailable` (there will never be a waveform for this item). Open set; treat unknown values as `unavailable`. 
  @BuiltValueField(wireName: r'state')
  String get state;

  /// The described part of a multi-file audiobook. Present only for multi-file books. 
  @BuiltValueField(wireName: r'partIndex')
  int? get partIndex;

  /// One amplitude per bucket in playback order, `0` silence and `255` full scale (`ready` only). Downsample to the pixel width being drawn. 
  @BuiltValueField(wireName: r'peaks')
  BuiltList<int>? get peaks;

  /// How many buckets `peaks` carries (`ready` only). Fixed by the catalog at 1000 today; read it rather than assuming, because an analysis version bump may change it. 
  @BuiltValueField(wireName: r'resolution')
  int? get resolution;

  /// Content hash of the analyzed audio essence, matching the download surface's `essenceHash`. A stored waveform whose hash no longer matches the stored audio is stale. 
  @BuiltValueField(wireName: r'essenceHash')
  String? get essenceHash;

  Waveform._();

  factory Waveform([void updates(WaveformBuilder b)]) = _$Waveform;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WaveformBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Waveform> get serializer => _$WaveformSerializer();
}

class _$WaveformSerializer implements PrimitiveSerializer<Waveform> {
  @override
  final Iterable<Type> types = const [Waveform, _$Waveform];

  @override
  final String wireName = r'Waveform';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Waveform object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'state';
    yield serializers.serialize(
      object.state,
      specifiedType: const FullType(String),
    );
    if (object.partIndex != null) {
      yield r'partIndex';
      yield serializers.serialize(
        object.partIndex,
        specifiedType: const FullType(int),
      );
    }
    if (object.peaks != null) {
      yield r'peaks';
      yield serializers.serialize(
        object.peaks,
        specifiedType: const FullType(BuiltList, [FullType(int)]),
      );
    }
    if (object.resolution != null) {
      yield r'resolution';
      yield serializers.serialize(
        object.resolution,
        specifiedType: const FullType(int),
      );
    }
    if (object.essenceHash != null) {
      yield r'essenceHash';
      yield serializers.serialize(
        object.essenceHash,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Waveform object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WaveformBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.state = valueDes;
          break;
        case r'partIndex':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.partIndex = valueDes;
          break;
        case r'peaks':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(int)]),
          ) as BuiltList<int>;
          result.peaks.replace(valueDes);
          break;
        case r'resolution':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.resolution = valueDes;
          break;
        case r'essenceHash':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.essenceHash = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Waveform deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WaveformBuilder();
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

