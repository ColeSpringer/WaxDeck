//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scrobbling_admin_config.g.dart';

/// The server-level scrobbling credential state.
///
/// Properties:
/// * [lastfmConfigured] - Whether a usable Last.fm API credential pair is in effect (users can link accounts and the connect button enables). 
/// * [lastfmSource] - Where the effective pair came from: `settings`, `environment`, or `none`. An open string. 
/// * [lastfmApiKey] - The effective API key, for display in the admin form. Present only when configured; the shared secret is never returned. 
/// * [lastfmSecretSet] - Whether a shared secret is stored.
@BuiltValue()
abstract class ScrobblingAdminConfig implements Built<ScrobblingAdminConfig, ScrobblingAdminConfigBuilder> {
  /// Whether a usable Last.fm API credential pair is in effect (users can link accounts and the connect button enables). 
  @BuiltValueField(wireName: r'lastfmConfigured')
  bool get lastfmConfigured;

  /// Where the effective pair came from: `settings`, `environment`, or `none`. An open string. 
  @BuiltValueField(wireName: r'lastfmSource')
  String get lastfmSource;

  /// The effective API key, for display in the admin form. Present only when configured; the shared secret is never returned. 
  @BuiltValueField(wireName: r'lastfmApiKey')
  String? get lastfmApiKey;

  /// Whether a shared secret is stored.
  @BuiltValueField(wireName: r'lastfmSecretSet')
  bool get lastfmSecretSet;

  ScrobblingAdminConfig._();

  factory ScrobblingAdminConfig([void updates(ScrobblingAdminConfigBuilder b)]) = _$ScrobblingAdminConfig;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ScrobblingAdminConfigBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ScrobblingAdminConfig> get serializer => _$ScrobblingAdminConfigSerializer();
}

class _$ScrobblingAdminConfigSerializer implements PrimitiveSerializer<ScrobblingAdminConfig> {
  @override
  final Iterable<Type> types = const [ScrobblingAdminConfig, _$ScrobblingAdminConfig];

  @override
  final String wireName = r'ScrobblingAdminConfig';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ScrobblingAdminConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'lastfmConfigured';
    yield serializers.serialize(
      object.lastfmConfigured,
      specifiedType: const FullType(bool),
    );
    yield r'lastfmSource';
    yield serializers.serialize(
      object.lastfmSource,
      specifiedType: const FullType(String),
    );
    if (object.lastfmApiKey != null) {
      yield r'lastfmApiKey';
      yield serializers.serialize(
        object.lastfmApiKey,
        specifiedType: const FullType(String),
      );
    }
    yield r'lastfmSecretSet';
    yield serializers.serialize(
      object.lastfmSecretSet,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ScrobblingAdminConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ScrobblingAdminConfigBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'lastfmConfigured':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.lastfmConfigured = valueDes;
          break;
        case r'lastfmSource':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastfmSource = valueDes;
          break;
        case r'lastfmApiKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastfmApiKey = valueDes;
          break;
        case r'lastfmSecretSet':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.lastfmSecretSet = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ScrobblingAdminConfig deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ScrobblingAdminConfigBuilder();
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

