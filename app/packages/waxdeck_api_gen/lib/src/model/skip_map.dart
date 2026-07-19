//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/skip_span.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'skip_map.g.dart';

/// Precomputed silence spans for one audio file, keyed to its audio essence and the upstream detector version. Spans are in the mapped file's own timeline (for a multi-file audiobook, the requested part's timeline, not the book's). 
///
/// Properties:
/// * [state] - `ready` (spans present), `pending` (analysis queued or running; poll again later), or `unavailable` (this item is not mapped: not spoken-word content, audio not fetched to the server yet, or the streaming sidecar cannot analyze). Open set; treat unknown values as `unavailable`. 
/// * [essenceHash] - Content hash of the mapped file's audio essence, matching the download surface's `essenceHash`; a stored map whose hash no longer matches the stored audio is stale. 
/// * [partIndex] - The mapped part of a multi-file audiobook. Present only for multi-file books. 
/// * [version] - Upstream silence-detector revision the map was built by.
/// * [thresholdDb] - Detection threshold in dBFS.
/// * [minSeconds] - Minimum span length in seconds.
/// * [spans] - Silence spans ordered by `startMs` (`ready` only).
/// * [updatedAt] - When the map was computed.
@BuiltValue()
abstract class SkipMap implements Built<SkipMap, SkipMapBuilder> {
  /// `ready` (spans present), `pending` (analysis queued or running; poll again later), or `unavailable` (this item is not mapped: not spoken-word content, audio not fetched to the server yet, or the streaming sidecar cannot analyze). Open set; treat unknown values as `unavailable`. 
  @BuiltValueField(wireName: r'state')
  String get state;

  /// Content hash of the mapped file's audio essence, matching the download surface's `essenceHash`; a stored map whose hash no longer matches the stored audio is stale. 
  @BuiltValueField(wireName: r'essenceHash')
  String? get essenceHash;

  /// The mapped part of a multi-file audiobook. Present only for multi-file books. 
  @BuiltValueField(wireName: r'partIndex')
  int? get partIndex;

  /// Upstream silence-detector revision the map was built by.
  @BuiltValueField(wireName: r'version')
  String? get version;

  /// Detection threshold in dBFS.
  @BuiltValueField(wireName: r'thresholdDb')
  double? get thresholdDb;

  /// Minimum span length in seconds.
  @BuiltValueField(wireName: r'minSeconds')
  double? get minSeconds;

  /// Silence spans ordered by `startMs` (`ready` only).
  @BuiltValueField(wireName: r'spans')
  BuiltList<SkipSpan>? get spans;

  /// When the map was computed.
  @BuiltValueField(wireName: r'updatedAt')
  DateTime? get updatedAt;

  SkipMap._();

  factory SkipMap([void updates(SkipMapBuilder b)]) = _$SkipMap;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SkipMapBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SkipMap> get serializer => _$SkipMapSerializer();
}

class _$SkipMapSerializer implements PrimitiveSerializer<SkipMap> {
  @override
  final Iterable<Type> types = const [SkipMap, _$SkipMap];

  @override
  final String wireName = r'SkipMap';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SkipMap object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'state';
    yield serializers.serialize(
      object.state,
      specifiedType: const FullType(String),
    );
    if (object.essenceHash != null) {
      yield r'essenceHash';
      yield serializers.serialize(
        object.essenceHash,
        specifiedType: const FullType(String),
      );
    }
    if (object.partIndex != null) {
      yield r'partIndex';
      yield serializers.serialize(
        object.partIndex,
        specifiedType: const FullType(int),
      );
    }
    if (object.version != null) {
      yield r'version';
      yield serializers.serialize(
        object.version,
        specifiedType: const FullType(String),
      );
    }
    if (object.thresholdDb != null) {
      yield r'thresholdDb';
      yield serializers.serialize(
        object.thresholdDb,
        specifiedType: const FullType(double),
      );
    }
    if (object.minSeconds != null) {
      yield r'minSeconds';
      yield serializers.serialize(
        object.minSeconds,
        specifiedType: const FullType(double),
      );
    }
    if (object.spans != null) {
      yield r'spans';
      yield serializers.serialize(
        object.spans,
        specifiedType: const FullType(BuiltList, [FullType(SkipSpan)]),
      );
    }
    if (object.updatedAt != null) {
      yield r'updatedAt';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SkipMap object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SkipMapBuilder result,
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
        case r'essenceHash':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.essenceHash = valueDes;
          break;
        case r'partIndex':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.partIndex = valueDes;
          break;
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.version = valueDes;
          break;
        case r'thresholdDb':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.thresholdDb = valueDes;
          break;
        case r'minSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.minSeconds = valueDes;
          break;
        case r'spans':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(SkipSpan)]),
          ) as BuiltList<SkipSpan>;
          result.spans.replace(valueDes);
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SkipMap deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SkipMapBuilder();
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

