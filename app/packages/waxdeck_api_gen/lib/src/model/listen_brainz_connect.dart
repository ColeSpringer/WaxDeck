//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'listen_brainz_connect.g.dart';

/// A ListenBrainz user token to link.
///
/// Properties:
/// * [token] - The user token from the ListenBrainz profile page.
/// * [apiUrl] - Base URL of a ListenBrainz-compatible API server. Omit for listenbrainz.org. 
@BuiltValue()
abstract class ListenBrainzConnect implements Built<ListenBrainzConnect, ListenBrainzConnectBuilder> {
  /// The user token from the ListenBrainz profile page.
  @BuiltValueField(wireName: r'token')
  String get token;

  /// Base URL of a ListenBrainz-compatible API server. Omit for listenbrainz.org. 
  @BuiltValueField(wireName: r'apiUrl')
  String? get apiUrl;

  ListenBrainzConnect._();

  factory ListenBrainzConnect([void updates(ListenBrainzConnectBuilder b)]) = _$ListenBrainzConnect;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListenBrainzConnectBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListenBrainzConnect> get serializer => _$ListenBrainzConnectSerializer();
}

class _$ListenBrainzConnectSerializer implements PrimitiveSerializer<ListenBrainzConnect> {
  @override
  final Iterable<Type> types = const [ListenBrainzConnect, _$ListenBrainzConnect];

  @override
  final String wireName = r'ListenBrainzConnect';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListenBrainzConnect object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'token';
    yield serializers.serialize(
      object.token,
      specifiedType: const FullType(String),
    );
    if (object.apiUrl != null) {
      yield r'apiUrl';
      yield serializers.serialize(
        object.apiUrl,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ListenBrainzConnect object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListenBrainzConnectBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.token = valueDes;
          break;
        case r'apiUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.apiUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ListenBrainzConnect deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListenBrainzConnectBuilder();
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

