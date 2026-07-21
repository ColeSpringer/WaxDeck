//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_command_frame.g.dart';

/// Client-to-server command on the WebSocket command bus (transport in `api/events.md`). Targets a session by id; `verb` is one of `play`, `pause`, `stop`, `seek`, `next`, `previous`, `set-volume`, `set-rate`, `set-queue`, `set-repeat`, `set-shuffle` (open string; unknown verbs answer an error frame). Arguments are absolute state, never deltas. Answered exactly once, with an ack or an error echoing `id`. 
///
/// Properties:
/// * [type] - Always `cmd`.
/// * [id] - Client-chosen correlation id, echoed on the answer.
/// * [sessionId] - The target session.
/// * [verb] - The command verb.
/// * [positionMs] - For `seek` and optionally `set-queue`.
/// * [volume] - For `set-volume`, 0 to 1.
/// * [rate] - For `set-rate`.
/// * [itemPids] - For `set-queue`, the new queue in play order.
/// * [index] - For `set-queue`, the entry to play.
/// * [repeat] - For `set-repeat`: `off`, `all`, or `one`.
/// * [shuffle] - For `set-shuffle`.
@BuiltValue()
abstract class WsCommandFrame implements Built<WsCommandFrame, WsCommandFrameBuilder> {
  /// Always `cmd`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// Client-chosen correlation id, echoed on the answer.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// The target session.
  @BuiltValueField(wireName: r'sessionId')
  String get sessionId;

  /// The command verb.
  @BuiltValueField(wireName: r'verb')
  String get verb;

  /// For `seek` and optionally `set-queue`.
  @BuiltValueField(wireName: r'positionMs')
  int? get positionMs;

  /// For `set-volume`, 0 to 1.
  @BuiltValueField(wireName: r'volume')
  double? get volume;

  /// For `set-rate`.
  @BuiltValueField(wireName: r'rate')
  double? get rate;

  /// For `set-queue`, the new queue in play order.
  @BuiltValueField(wireName: r'itemPids')
  BuiltList<String>? get itemPids;

  /// For `set-queue`, the entry to play.
  @BuiltValueField(wireName: r'index')
  int? get index;

  /// For `set-repeat`: `off`, `all`, or `one`.
  @BuiltValueField(wireName: r'repeat')
  String? get repeat;

  /// For `set-shuffle`.
  @BuiltValueField(wireName: r'shuffle')
  bool? get shuffle;

  WsCommandFrame._();

  factory WsCommandFrame([void updates(WsCommandFrameBuilder b)]) = _$WsCommandFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsCommandFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsCommandFrame> get serializer => _$WsCommandFrameSerializer();
}

class _$WsCommandFrameSerializer implements PrimitiveSerializer<WsCommandFrame> {
  @override
  final Iterable<Type> types = const [WsCommandFrame, _$WsCommandFrame];

  @override
  final String wireName = r'WsCommandFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsCommandFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'sessionId';
    yield serializers.serialize(
      object.sessionId,
      specifiedType: const FullType(String),
    );
    yield r'verb';
    yield serializers.serialize(
      object.verb,
      specifiedType: const FullType(String),
    );
    if (object.positionMs != null) {
      yield r'positionMs';
      yield serializers.serialize(
        object.positionMs,
        specifiedType: const FullType(int),
      );
    }
    if (object.volume != null) {
      yield r'volume';
      yield serializers.serialize(
        object.volume,
        specifiedType: const FullType(double),
      );
    }
    if (object.rate != null) {
      yield r'rate';
      yield serializers.serialize(
        object.rate,
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
    if (object.index != null) {
      yield r'index';
      yield serializers.serialize(
        object.index,
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
    WsCommandFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsCommandFrameBuilder result,
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
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'sessionId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sessionId = valueDes;
          break;
        case r'verb':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.verb = valueDes;
          break;
        case r'positionMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.positionMs = valueDes;
          break;
        case r'volume':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.volume = valueDes;
          break;
        case r'rate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.rate = valueDes;
          break;
        case r'itemPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.itemPids.replace(valueDes);
          break;
        case r'index':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.index = valueDes;
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
  WsCommandFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsCommandFrameBuilder();
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

