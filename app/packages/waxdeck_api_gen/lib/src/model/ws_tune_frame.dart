//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ws_tune_frame.g.dart';

/// Client-to-server: name the station this client is listening to, so a `radio` invalidation reaches the clients it is about rather than every connection. A new tune replaces the previous one; omitting `station` says this client is no longer listening. Never acked, and never refused: an unknown pid simply matches no landing. A client that never tunes hears no `radio` invalidations, which is what a client with no station to draw wants. 
///
/// Properties:
/// * [type] - Always `tune`.
/// * [station] - The station being listened to.
@BuiltValue()
abstract class WsTuneFrame implements Built<WsTuneFrame, WsTuneFrameBuilder> {
  /// Always `tune`.
  @BuiltValueField(wireName: r'type')
  String get type;

  /// The station being listened to.
  @BuiltValueField(wireName: r'station')
  String? get station;

  WsTuneFrame._();

  factory WsTuneFrame([void updates(WsTuneFrameBuilder b)]) = _$WsTuneFrame;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WsTuneFrameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WsTuneFrame> get serializer => _$WsTuneFrameSerializer();
}

class _$WsTuneFrameSerializer implements PrimitiveSerializer<WsTuneFrame> {
  @override
  final Iterable<Type> types = const [WsTuneFrame, _$WsTuneFrame];

  @override
  final String wireName = r'WsTuneFrame';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WsTuneFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    if (object.station != null) {
      yield r'station';
      yield serializers.serialize(
        object.station,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WsTuneFrame object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WsTuneFrameBuilder result,
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
        case r'station':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.station = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WsTuneFrame deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WsTuneFrameBuilder();
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

