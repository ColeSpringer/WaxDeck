//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'oidc_provider.g.dart';

/// One configured OIDC provider.
///
/// Properties:
/// * [id] - Stable provider id, referenced by `/auth/oidc/start`.
/// * [displayName] - Human-readable name for the login button.
/// * [startUrl] - Origin-relative URL that starts this provider's login flow (web mode; other modes add their query parameters). 
@BuiltValue()
abstract class OidcProvider implements Built<OidcProvider, OidcProviderBuilder> {
  /// Stable provider id, referenced by `/auth/oidc/start`.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// Human-readable name for the login button.
  @BuiltValueField(wireName: r'displayName')
  String get displayName;

  /// Origin-relative URL that starts this provider's login flow (web mode; other modes add their query parameters). 
  @BuiltValueField(wireName: r'startUrl')
  String get startUrl;

  OidcProvider._();

  factory OidcProvider([void updates(OidcProviderBuilder b)]) = _$OidcProvider;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OidcProviderBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OidcProvider> get serializer => _$OidcProviderSerializer();
}

class _$OidcProviderSerializer implements PrimitiveSerializer<OidcProvider> {
  @override
  final Iterable<Type> types = const [OidcProvider, _$OidcProvider];

  @override
  final String wireName = r'OidcProvider';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OidcProvider object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'displayName';
    yield serializers.serialize(
      object.displayName,
      specifiedType: const FullType(String),
    );
    yield r'startUrl';
    yield serializers.serialize(
      object.startUrl,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OidcProvider object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OidcProviderBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'startUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.startUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OidcProvider deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OidcProviderBuilder();
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

