//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/cast_preflight_base.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cast_device_probe.g.dart';

/// A device probe's answer: the endpoint it ran against, and one row per candidate base carrying both verdicts - the server's own reachability check and what the device did. 
///
/// Properties:
/// * [endpointId] - The endpoint that was probed.
/// * [name] - Its display name, for a one-call rendering.
/// * [kind] - `cast` or `dlna` (open string).
/// * [bases] - The addresses the device was put to, in the order sessions try them. Short of the full candidate list where the device stopped answering partway through. 
@BuiltValue()
abstract class CastDeviceProbe implements Built<CastDeviceProbe, CastDeviceProbeBuilder> {
  /// The endpoint that was probed.
  @BuiltValueField(wireName: r'endpointId')
  String get endpointId;

  /// Its display name, for a one-call rendering.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// `cast` or `dlna` (open string).
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// The addresses the device was put to, in the order sessions try them. Short of the full candidate list where the device stopped answering partway through. 
  @BuiltValueField(wireName: r'bases')
  BuiltList<CastPreflightBase> get bases;

  CastDeviceProbe._();

  factory CastDeviceProbe([void updates(CastDeviceProbeBuilder b)]) = _$CastDeviceProbe;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CastDeviceProbeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CastDeviceProbe> get serializer => _$CastDeviceProbeSerializer();
}

class _$CastDeviceProbeSerializer implements PrimitiveSerializer<CastDeviceProbe> {
  @override
  final Iterable<Type> types = const [CastDeviceProbe, _$CastDeviceProbe];

  @override
  final String wireName = r'CastDeviceProbe';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CastDeviceProbe object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'endpointId';
    yield serializers.serialize(
      object.endpointId,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    yield r'bases';
    yield serializers.serialize(
      object.bases,
      specifiedType: const FullType(BuiltList, [FullType(CastPreflightBase)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CastDeviceProbe object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CastDeviceProbeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'endpointId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.endpointId = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'bases':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(CastPreflightBase)]),
          ) as BuiltList<CastPreflightBase>;
          result.bases.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CastDeviceProbe deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CastDeviceProbeBuilder();
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

