//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/oidc_provider.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'oidc_providers.g.dart';

/// The configured OIDC providers.
///
/// Properties:
/// * [providers] 
@BuiltValue()
abstract class OidcProviders implements Built<OidcProviders, OidcProvidersBuilder> {
  @BuiltValueField(wireName: r'providers')
  BuiltList<OidcProvider> get providers;

  OidcProviders._();

  factory OidcProviders([void updates(OidcProvidersBuilder b)]) = _$OidcProviders;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OidcProvidersBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OidcProviders> get serializer => _$OidcProvidersSerializer();
}

class _$OidcProvidersSerializer implements PrimitiveSerializer<OidcProviders> {
  @override
  final Iterable<Type> types = const [OidcProviders, _$OidcProviders];

  @override
  final String wireName = r'OidcProviders';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OidcProviders object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'providers';
    yield serializers.serialize(
      object.providers,
      specifiedType: const FullType(BuiltList, [FullType(OidcProvider)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OidcProviders object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OidcProvidersBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'providers':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(OidcProvider)]),
          ) as BuiltList<OidcProvider>;
          result.providers.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OidcProviders deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OidcProvidersBuilder();
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

