//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'play_info.g.dart';

/// Everything a client needs to begin playback of one item.
///
/// Properties:
/// * [pid] - The resolved item's PID.
/// * [url] - Origin-relative, media-token-authenticated stream URL. Short TTL; re-request play-info on expiry or a `stream-stale` error. 
/// * [mimeType] - MIME type the stream will be served as.
/// * [durationMs] - Duration in milliseconds.
/// * [seekable] - Whether the stream supports sample-exact seeking.
/// * [expiresAt] - When the embedded media token stops being accepted.
/// * [partIndex] - Zero-based index of the resolved part within a multi-file audiobook. Present exactly when `partCount` is. 
/// * [partCount] - Number of parts in a multi-file audiobook. Present only for multi-file books; single-file items omit the part fields entirely. 
/// * [partStartMs] - Book-timeline millisecond offset where the resolved part begins. In-part positions plus this offset give the book-timeline positions that play-state expects. Present exactly when `partCount` is. 
/// * [voiceBoost] - True when the stream applies server-side spoken-word loudness normalization. Absent or false otherwise, including when it was requested but cannot be applied yet (unsupported by the sidecar, or loudness not measured yet). 
/// * [spanStartMs] - Present exactly with `spanEndMs`, and only when the url serves the item's whole backing file while the item is a window into it (direct playback of a track carved from a larger rip, on a server running without the streaming engine): the client must play only the [`spanStartMs`, `spanEndMs`) window of the served audio. Absent whenever the server cuts the stream itself. `durationMs` remains the item's own duration, never the backing file's. 
/// * [spanEndMs] - End of the playback window in served-audio milliseconds. Present exactly when `spanStartMs` is. 
@BuiltValue()
abstract class PlayInfo implements Built<PlayInfo, PlayInfoBuilder> {
  /// The resolved item's PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Origin-relative, media-token-authenticated stream URL. Short TTL; re-request play-info on expiry or a `stream-stale` error. 
  @BuiltValueField(wireName: r'url')
  String get url;

  /// MIME type the stream will be served as.
  @BuiltValueField(wireName: r'mimeType')
  String get mimeType;

  /// Duration in milliseconds.
  @BuiltValueField(wireName: r'durationMs')
  int get durationMs;

  /// Whether the stream supports sample-exact seeking.
  @BuiltValueField(wireName: r'seekable')
  bool get seekable;

  /// When the embedded media token stops being accepted.
  @BuiltValueField(wireName: r'expiresAt')
  DateTime get expiresAt;

  /// Zero-based index of the resolved part within a multi-file audiobook. Present exactly when `partCount` is. 
  @BuiltValueField(wireName: r'partIndex')
  int? get partIndex;

  /// Number of parts in a multi-file audiobook. Present only for multi-file books; single-file items omit the part fields entirely. 
  @BuiltValueField(wireName: r'partCount')
  int? get partCount;

  /// Book-timeline millisecond offset where the resolved part begins. In-part positions plus this offset give the book-timeline positions that play-state expects. Present exactly when `partCount` is. 
  @BuiltValueField(wireName: r'partStartMs')
  int? get partStartMs;

  /// True when the stream applies server-side spoken-word loudness normalization. Absent or false otherwise, including when it was requested but cannot be applied yet (unsupported by the sidecar, or loudness not measured yet). 
  @BuiltValueField(wireName: r'voiceBoost')
  bool? get voiceBoost;

  /// Present exactly with `spanEndMs`, and only when the url serves the item's whole backing file while the item is a window into it (direct playback of a track carved from a larger rip, on a server running without the streaming engine): the client must play only the [`spanStartMs`, `spanEndMs`) window of the served audio. Absent whenever the server cuts the stream itself. `durationMs` remains the item's own duration, never the backing file's. 
  @BuiltValueField(wireName: r'spanStartMs')
  int? get spanStartMs;

  /// End of the playback window in served-audio milliseconds. Present exactly when `spanStartMs` is. 
  @BuiltValueField(wireName: r'spanEndMs')
  int? get spanEndMs;

  PlayInfo._();

  factory PlayInfo([void updates(PlayInfoBuilder b)]) = _$PlayInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlayInfoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlayInfo> get serializer => _$PlayInfoSerializer();
}

class _$PlayInfoSerializer implements PrimitiveSerializer<PlayInfo> {
  @override
  final Iterable<Type> types = const [PlayInfo, _$PlayInfo];

  @override
  final String wireName = r'PlayInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlayInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
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
    yield r'seekable';
    yield serializers.serialize(
      object.seekable,
      specifiedType: const FullType(bool),
    );
    yield r'expiresAt';
    yield serializers.serialize(
      object.expiresAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.partIndex != null) {
      yield r'partIndex';
      yield serializers.serialize(
        object.partIndex,
        specifiedType: const FullType(int),
      );
    }
    if (object.partCount != null) {
      yield r'partCount';
      yield serializers.serialize(
        object.partCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.partStartMs != null) {
      yield r'partStartMs';
      yield serializers.serialize(
        object.partStartMs,
        specifiedType: const FullType(int),
      );
    }
    if (object.voiceBoost != null) {
      yield r'voiceBoost';
      yield serializers.serialize(
        object.voiceBoost,
        specifiedType: const FullType(bool),
      );
    }
    if (object.spanStartMs != null) {
      yield r'spanStartMs';
      yield serializers.serialize(
        object.spanStartMs,
        specifiedType: const FullType(int),
      );
    }
    if (object.spanEndMs != null) {
      yield r'spanEndMs';
      yield serializers.serialize(
        object.spanEndMs,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlayInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlayInfoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
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
        case r'seekable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.seekable = valueDes;
          break;
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        case r'partIndex':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.partIndex = valueDes;
          break;
        case r'partCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.partCount = valueDes;
          break;
        case r'partStartMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.partStartMs = valueDes;
          break;
        case r'voiceBoost':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.voiceBoost = valueDes;
          break;
        case r'spanStartMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.spanStartMs = valueDes;
          break;
        case r'spanEndMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.spanEndMs = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlayInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlayInfoBuilder();
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

