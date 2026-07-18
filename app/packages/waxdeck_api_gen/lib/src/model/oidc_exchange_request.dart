//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'oidc_exchange_request.g.dart';

/// A one-time OIDC completion code to redeem for a session.
///
/// Properties:
/// * [code] - The one-time code delivered by the flow's redirect or code page.
/// * [verifier] - The secret whose SHA-256 was sent as `challenge` when the flow started. Required when the flow carried a challenge; a missing or wrong value fails the exchange. 
/// * [deviceName] - Device-list label for the resulting session.
@BuiltValue()
abstract class OidcExchangeRequest implements Built<OidcExchangeRequest, OidcExchangeRequestBuilder> {
  /// The one-time code delivered by the flow's redirect or code page.
  @BuiltValueField(wireName: r'code')
  String get code;

  /// The secret whose SHA-256 was sent as `challenge` when the flow started. Required when the flow carried a challenge; a missing or wrong value fails the exchange. 
  @BuiltValueField(wireName: r'verifier')
  String? get verifier;

  /// Device-list label for the resulting session.
  @BuiltValueField(wireName: r'deviceName')
  String? get deviceName;

  OidcExchangeRequest._();

  factory OidcExchangeRequest([void updates(OidcExchangeRequestBuilder b)]) = _$OidcExchangeRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OidcExchangeRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OidcExchangeRequest> get serializer => _$OidcExchangeRequestSerializer();
}

class _$OidcExchangeRequestSerializer implements PrimitiveSerializer<OidcExchangeRequest> {
  @override
  final Iterable<Type> types = const [OidcExchangeRequest, _$OidcExchangeRequest];

  @override
  final String wireName = r'OidcExchangeRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OidcExchangeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
    if (object.verifier != null) {
      yield r'verifier';
      yield serializers.serialize(
        object.verifier,
        specifiedType: const FullType(String),
      );
    }
    if (object.deviceName != null) {
      yield r'deviceName';
      yield serializers.serialize(
        object.deviceName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OidcExchangeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OidcExchangeRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'verifier':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.verifier = valueDes;
          break;
        case r'deviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.deviceName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OidcExchangeRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OidcExchangeRequestBuilder();
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

