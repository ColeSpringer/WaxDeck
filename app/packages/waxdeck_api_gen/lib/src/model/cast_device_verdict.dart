//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cast_device_verdict.g.dart';

/// One device's trial run against one advertise base: a second of silence loaded onto it, and what it did. 
///
/// Properties:
/// * [verdict] - `played` (the device fetched the probe through this address), `failed` (it refused the load or the stream, and `detail` carries what it said), or `timeout` (it never fetched it, which is what an address the device cannot reach looks like). Open string. 
/// * [detail] - What the device or the protocol said, verbatim where there is anything to quote: a cast idle reason, a UPnP fault. 
/// * [latencyMs] - Milliseconds from handing the device the URL to its answer, which is roughly what a listener waits before the first sound. On a verdict that is not `played` it is how long the device was given. 
@BuiltValue()
abstract class CastDeviceVerdict implements Built<CastDeviceVerdict, CastDeviceVerdictBuilder> {
  /// `played` (the device fetched the probe through this address), `failed` (it refused the load or the stream, and `detail` carries what it said), or `timeout` (it never fetched it, which is what an address the device cannot reach looks like). Open string. 
  @BuiltValueField(wireName: r'verdict')
  String get verdict;

  /// What the device or the protocol said, verbatim where there is anything to quote: a cast idle reason, a UPnP fault. 
  @BuiltValueField(wireName: r'detail')
  String? get detail;

  /// Milliseconds from handing the device the URL to its answer, which is roughly what a listener waits before the first sound. On a verdict that is not `played` it is how long the device was given. 
  @BuiltValueField(wireName: r'latencyMs')
  int get latencyMs;

  CastDeviceVerdict._();

  factory CastDeviceVerdict([void updates(CastDeviceVerdictBuilder b)]) = _$CastDeviceVerdict;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CastDeviceVerdictBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CastDeviceVerdict> get serializer => _$CastDeviceVerdictSerializer();
}

class _$CastDeviceVerdictSerializer implements PrimitiveSerializer<CastDeviceVerdict> {
  @override
  final Iterable<Type> types = const [CastDeviceVerdict, _$CastDeviceVerdict];

  @override
  final String wireName = r'CastDeviceVerdict';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CastDeviceVerdict object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'verdict';
    yield serializers.serialize(
      object.verdict,
      specifiedType: const FullType(String),
    );
    if (object.detail != null) {
      yield r'detail';
      yield serializers.serialize(
        object.detail,
        specifiedType: const FullType(String),
      );
    }
    yield r'latencyMs';
    yield serializers.serialize(
      object.latencyMs,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CastDeviceVerdict object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CastDeviceVerdictBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'verdict':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.verdict = valueDes;
          break;
        case r'detail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.detail = valueDes;
          break;
        case r'latencyMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.latencyMs = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CastDeviceVerdict deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CastDeviceVerdictBuilder();
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

