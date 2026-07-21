//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_session_report_frame.g.dart';

/// Client-to-server state report from a playing client: sent on every state change (play, pause, seek, track change, queue change) and at least every five seconds while playing. The steady fields (`playing`, `positionMs`, `index`, `rate`, `volume`, `repeat`, `shuffle`) carry current truth on every report; a track advance is just a report with the new `index`. `itemPids` rides only the reports where the queue itself changed, together with a bumped `queueVersion`, plus the first report of a connection that is already playing (the one that creates or re-creates the mirror session; a creating report without `itemPids` is ignored, since a session without a queue is unrenderable). The server answers a creating report with a `session` frame carrying the assigned id; other reports are unacknowledged. 
///
/// Properties:
/// * [type] - Always `session-report`.
/// * [playing] - Whether local playback is running.
/// * [positionMs] - Position within the current entry.
/// * [index] - Zero-based index of the current entry.
/// * [rate] - Playback rate.
/// * [volume] - Local volume, 0 to 1, when the client controls one.
/// * [itemPids] - The queue in play order, only on reports where it changed (and on the creating report). 
/// * [queueVersion] - The client's queue generation, bumped when its queue changes. An edge signal only: the version the server publishes on the session is its own monotone counter. 
/// * [repeat] - `off`, `all`, or `one`.
/// * [shuffle] - Whether shuffle is on.
@BuiltValue()
abstract class WsSessionReportFrame implements Built<WsSessionReportFrame, WsSessionReportFrameBuilder> {
  /// Always `session-report`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// Whether local playback is running.
  @BuiltValueField(wireName: r'playing')
  bool get playing;

  /// Position within the current entry.
  @BuiltValueField(wireName: r'positionMs')
  int get positionMs;

  /// Zero-based index of the current entry.
  @BuiltValueField(wireName: r'index')
  int get index;

  /// Playback rate.
  @BuiltValueField(wireName: r'rate')
  double? get rate;

  /// Local volume, 0 to 1, when the client controls one.
  @BuiltValueField(wireName: r'volume')
  double? get volume;

  /// The queue in play order, only on reports where it changed (and on the creating report). 
  @BuiltValueField(wireName: r'itemPids')
  BuiltList<String>? get itemPids;

  /// The client's queue generation, bumped when its queue changes. An edge signal only: the version the server publishes on the session is its own monotone counter. 
  @BuiltValueField(wireName: r'queueVersion')
  int? get queueVersion;

  /// `off`, `all`, or `one`.
  @BuiltValueField(wireName: r'repeat')
  String? get repeat;

  /// Whether shuffle is on.
  @BuiltValueField(wireName: r'shuffle')
  bool? get shuffle;

  WsSessionReportFrame._();

  factory WsSessionReportFrame([void updates(WsSessionReportFrameBuilder b)]) = _$WsSessionReportFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsSessionReportFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsSessionReportFrame> get serializer => _$WsSessionReportFrameSerializer();
}

class _$WsSessionReportFrameSerializer implements PrimitiveSerializer<WsSessionReportFrame> {
  @override
  final Iterable<Type> types = const [WsSessionReportFrame, _$WsSessionReportFrame];

  @override
  final String wireName = r'WsSessionReportFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsSessionReportFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    yield r'playing';
    yield serializers.serialize(
      object.playing,
      specifiedType: const FullType(bool),
    );
    yield r'positionMs';
    yield serializers.serialize(
      object.positionMs,
      specifiedType: const FullType(int),
    );
    yield r'index';
    yield serializers.serialize(
      object.index,
      specifiedType: const FullType(int),
    );
    if (object.rate != null) {
      yield r'rate';
      yield serializers.serialize(
        object.rate,
        specifiedType: const FullType(double),
      );
    }
    if (object.volume != null) {
      yield r'volume';
      yield serializers.serialize(
        object.volume,
        specifiedType: const FullType(double),
      );
    }
    if (object.itemPids != null) {
      yield r'itemPids';
      yield serializers.serialize(
        object.itemPids,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.queueVersion != null) {
      yield r'queueVersion';
      yield serializers.serialize(
        object.queueVersion,
        specifiedType: const FullType(int),
      );
    }
    if (object.repeat != null) {
      yield r'repeat';
      yield serializers.serialize(
        object.repeat,
        specifiedType: const FullType(String),
      );
    }
    if (object.shuffle != null) {
      yield r'shuffle';
      yield serializers.serialize(
        object.shuffle,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WsSessionReportFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsSessionReportFrameBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.type = valueDes;
          break;
        case r'playing':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.playing = valueDes;
          break;
        case r'positionMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.positionMs = valueDes;
          break;
        case r'index':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.index = valueDes;
          break;
        case r'rate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.rate = valueDes;
          break;
        case r'volume':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.volume = valueDes;
          break;
        case r'itemPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.itemPids.replace(valueDes);
          break;
        case r'queueVersion':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.queueVersion = valueDes;
          break;
        case r'repeat':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.repeat = valueDes;
          break;
        case r'shuffle':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.shuffle = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WsSessionReportFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsSessionReportFrameBuilder();
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

