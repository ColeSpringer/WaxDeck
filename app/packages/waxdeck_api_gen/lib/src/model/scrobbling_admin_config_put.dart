//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scrobbling_admin_config_put.g.dart';

/// A Last.fm API credential change: both values to set, both empty to clear back to environment credentials. 
///
/// Properties:
/// * [lastfmApiKey] - The Last.fm API key.
/// * [lastfmSecret] - The Last.fm shared secret.
@BuiltValue()
abstract class ScrobblingAdminConfigPut implements Built<ScrobblingAdminConfigPut, ScrobblingAdminConfigPutBuilder> {
  /// The Last.fm API key.
  @BuiltValueField(wireName: r'lastfmApiKey')
  String get lastfmApiKey;

  /// The Last.fm shared secret.
  @BuiltValueField(wireName: r'lastfmSecret')
  String get lastfmSecret;

  ScrobblingAdminConfigPut._();

  factory ScrobblingAdminConfigPut([void updates(ScrobblingAdminConfigPutBuilder b)]) = _$ScrobblingAdminConfigPut;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ScrobblingAdminConfigPutBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ScrobblingAdminConfigPut> get serializer => _$ScrobblingAdminConfigPutSerializer();
}

class _$ScrobblingAdminConfigPutSerializer implements PrimitiveSerializer<ScrobblingAdminConfigPut> {
  @override
  final Iterable<Type> types = const [ScrobblingAdminConfigPut, _$ScrobblingAdminConfigPut];

  @override
  final String wireName = r'ScrobblingAdminConfigPut';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ScrobblingAdminConfigPut object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'lastfmApiKey';
    yield serializers.serialize(
      object.lastfmApiKey,
      specifiedType: const FullType(String),
    );
    yield r'lastfmSecret';
    yield serializers.serialize(
      object.lastfmSecret,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ScrobblingAdminConfigPut object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ScrobblingAdminConfigPutBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'lastfmApiKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastfmApiKey = valueDes;
          break;
        case r'lastfmSecret':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastfmSecret = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ScrobblingAdminConfigPut deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ScrobblingAdminConfigPutBuilder();
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

