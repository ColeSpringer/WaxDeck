//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'streaming_engine_state.g.dart';

/// Whether the streaming engine is set up, answering, and what it offers. Without it, originals play directly: no transcoding, no gapless queue timelines, no voice boost, and no file tools. 
///
/// Properties:
/// * [configured] - An engine URL is set.
/// * [connected] - The engine answered its capabilities and is being probed. False while a configured engine is not reachable. 
/// * [timelines] - It renders a queue as one gapless timeline. False while not connected. 
/// * [voiceBoost] - It applies voice boost to spoken word. False while not connected. 
/// * [fileTools] - It runs the file tools (book merge and split, cue splits) and the silence analysis trimming reads. False while not connected. 
@BuiltValue()
abstract class StreamingEngineState implements Built<StreamingEngineState, StreamingEngineStateBuilder> {
  /// An engine URL is set.
  @BuiltValueField(wireName: r'configured')
  bool get configured;

  /// The engine answered its capabilities and is being probed. False while a configured engine is not reachable. 
  @BuiltValueField(wireName: r'connected')
  bool get connected;

  /// It renders a queue as one gapless timeline. False while not connected. 
  @BuiltValueField(wireName: r'timelines')
  bool get timelines;

  /// It applies voice boost to spoken word. False while not connected. 
  @BuiltValueField(wireName: r'voiceBoost')
  bool get voiceBoost;

  /// It runs the file tools (book merge and split, cue splits) and the silence analysis trimming reads. False while not connected. 
  @BuiltValueField(wireName: r'fileTools')
  bool get fileTools;

  StreamingEngineState._();

  factory StreamingEngineState([void updates(StreamingEngineStateBuilder b)]) = _$StreamingEngineState;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(StreamingEngineStateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<StreamingEngineState> get serializer => _$StreamingEngineStateSerializer();
}

class _$StreamingEngineStateSerializer implements PrimitiveSerializer<StreamingEngineState> {
  @override
  final Iterable<Type> types = const [StreamingEngineState, _$StreamingEngineState];

  @override
  final String wireName = r'StreamingEngineState';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    StreamingEngineState object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'configured';
    yield serializers.serialize(
      object.configured,
      specifiedType: const FullType(bool),
    );
    yield r'connected';
    yield serializers.serialize(
      object.connected,
      specifiedType: const FullType(bool),
    );
    yield r'timelines';
    yield serializers.serialize(
      object.timelines,
      specifiedType: const FullType(bool),
    );
    yield r'voiceBoost';
    yield serializers.serialize(
      object.voiceBoost,
      specifiedType: const FullType(bool),
    );
    yield r'fileTools';
    yield serializers.serialize(
      object.fileTools,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    StreamingEngineState object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required StreamingEngineStateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'configured':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.configured = valueDes;
          break;
        case r'connected':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.connected = valueDes;
          break;
        case r'timelines':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.timelines = valueDes;
          break;
        case r'voiceBoost':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.voiceBoost = valueDes;
          break;
        case r'fileTools':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.fileTools = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  StreamingEngineState deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = StreamingEngineStateBuilder();
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


