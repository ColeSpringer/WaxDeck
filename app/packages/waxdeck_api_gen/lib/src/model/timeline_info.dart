//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/timeline_boundary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'timeline_info.g.dart';

/// A minted gapless timeline: one HLS stream URL that plays the whole queue, plus the per-member boundaries to map positions. 
///
/// Properties:
/// * [url] - Origin-relative, media-token-authenticated HLS playlist URL for the whole timeline. The token lives at least the timeline's duration plus margin; re-request this endpoint on `stream-stale`, on a `not-found` fetch (the engine aged the timeline out), or after `expiresAt`. 
/// * [mimeType] - Always an HLS playlist type.
/// * [durationMs] - The combined timeline's duration.
/// * [expiresAt] - When the embedded media token stops being accepted.
/// * [envelopeRate] - Sample rate the boundary offsets are measured at (the maximum member rate). 
/// * [crossfadeSeconds] - The crossfade the timeline was minted with, when nonzero.
/// * [boundaries] - Per-member placement, in queue order.
@BuiltValue()
abstract class TimelineInfo implements Built<TimelineInfo, TimelineInfoBuilder> {
  /// Origin-relative, media-token-authenticated HLS playlist URL for the whole timeline. The token lives at least the timeline's duration plus margin; re-request this endpoint on `stream-stale`, on a `not-found` fetch (the engine aged the timeline out), or after `expiresAt`. 
  @BuiltValueField(wireName: r'url')
  String get url;

  /// Always an HLS playlist type.
  @BuiltValueField(wireName: r'mimeType')
  String get mimeType;

  /// The combined timeline's duration.
  @BuiltValueField(wireName: r'durationMs')
  int get durationMs;

  /// When the embedded media token stops being accepted.
  @BuiltValueField(wireName: r'expiresAt')
  DateTime get expiresAt;

  /// Sample rate the boundary offsets are measured at (the maximum member rate). 
  @BuiltValueField(wireName: r'envelopeRate')
  int get envelopeRate;

  /// The crossfade the timeline was minted with, when nonzero.
  @BuiltValueField(wireName: r'crossfadeSeconds')
  double? get crossfadeSeconds;

  /// Per-member placement, in queue order.
  @BuiltValueField(wireName: r'boundaries')
  BuiltList<TimelineBoundary> get boundaries;

  TimelineInfo._();

  factory TimelineInfo([void updates(TimelineInfoBuilder b)]) = _$TimelineInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TimelineInfoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TimelineInfo> get serializer => _$TimelineInfoSerializer();
}

class _$TimelineInfoSerializer implements PrimitiveSerializer<TimelineInfo> {
  @override
  final Iterable<Type> types = const [TimelineInfo, _$TimelineInfo];

  @override
  final String wireName = r'TimelineInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TimelineInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'url';
    yield serializers.serialize(
      object.url,
      specifiedType: const FullType(String),
    );
    yield r'mimeType';
    yield serializers.serialize(
      object.mimeType,
      specifiedType: const FullType(String),
    );
    yield r'durationMs';
    yield serializers.serialize(
      object.durationMs,
      specifiedType: const FullType(int),
    );
    yield r'expiresAt';
    yield serializers.serialize(
      object.expiresAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'envelopeRate';
    yield serializers.serialize(
      object.envelopeRate,
      specifiedType: const FullType(int),
    );
    if (object.crossfadeSeconds != null) {
      yield r'crossfadeSeconds';
      yield serializers.serialize(
        object.crossfadeSeconds,
        specifiedType: const FullType(double),
      );
    }
    yield r'boundaries';
    yield serializers.serialize(
      object.boundaries,
      specifiedType: const FullType(BuiltList, [FullType(TimelineBoundary)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TimelineInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TimelineInfoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'mimeType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mimeType = valueDes;
          break;
        case r'durationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMs = valueDes;
          break;
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        case r'envelopeRate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.envelopeRate = valueDes;
          break;
        case r'crossfadeSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.crossfadeSeconds = valueDes;
          break;
        case r'boundaries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TimelineBoundary)]),
          ) as BuiltList<TimelineBoundary>;
          result.boundaries.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TimelineInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TimelineInfoBuilder();
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

