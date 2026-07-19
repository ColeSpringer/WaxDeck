//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scrobbler.g.dart';

/// One outbound scrobbling connection slot.
///
/// Properties:
/// * [service] - `lastfm` or `listenbrainz`. A string, not a closed enum; clients must skip services they do not recognize. 
/// * [available] - True when the server can offer this service (Last.fm requires server-configured API credentials). 
/// * [connected] - True when the caller has linked an account.
/// * [username] - The linked account's username, when the service reports one. 
/// * [apiUrl] - The API base a ListenBrainz-compatible connection points at. Absent for listenbrainz.org and for Last.fm. 
/// * [lastSuccessAt] - When this connection last delivered a scrobble. Absent until the first delivery succeeds. Reconnecting resets it: the stamp belongs to the current credential. 
/// * [lastError] - The most recent delivery failure, present only while the connection is unhealthy: set when a delivery attempt fails, cleared by the next successful delivery and by reconnecting. A connection can carry both lastSuccessAt and lastError (it worked before it broke). A short human-readable summary suitable for display; never contains the credential. All three delivery stamps are absent whenever connected is false. 
/// * [lastErrorAt] - When lastError was recorded. Present exactly when lastError is. 
@BuiltValue()
abstract class Scrobbler implements Built<Scrobbler, ScrobblerBuilder> {
  /// `lastfm` or `listenbrainz`. A string, not a closed enum; clients must skip services they do not recognize. 
  @BuiltValueField(wireName: r'service')
  String get service;

  /// True when the server can offer this service (Last.fm requires server-configured API credentials). 
  @BuiltValueField(wireName: r'available')
  bool get available;

  /// True when the caller has linked an account.
  @BuiltValueField(wireName: r'connected')
  bool get connected;

  /// The linked account's username, when the service reports one. 
  @BuiltValueField(wireName: r'username')
  String? get username;

  /// The API base a ListenBrainz-compatible connection points at. Absent for listenbrainz.org and for Last.fm. 
  @BuiltValueField(wireName: r'apiUrl')
  String? get apiUrl;

  /// When this connection last delivered a scrobble. Absent until the first delivery succeeds. Reconnecting resets it: the stamp belongs to the current credential. 
  @BuiltValueField(wireName: r'lastSuccessAt')
  DateTime? get lastSuccessAt;

  /// The most recent delivery failure, present only while the connection is unhealthy: set when a delivery attempt fails, cleared by the next successful delivery and by reconnecting. A connection can carry both lastSuccessAt and lastError (it worked before it broke). A short human-readable summary suitable for display; never contains the credential. All three delivery stamps are absent whenever connected is false. 
  @BuiltValueField(wireName: r'lastError')
  String? get lastError;

  /// When lastError was recorded. Present exactly when lastError is. 
  @BuiltValueField(wireName: r'lastErrorAt')
  DateTime? get lastErrorAt;

  Scrobbler._();

  factory Scrobbler([void updates(ScrobblerBuilder b)]) = _$Scrobbler;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ScrobblerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Scrobbler> get serializer => _$ScrobblerSerializer();
}

class _$ScrobblerSerializer implements PrimitiveSerializer<Scrobbler> {
  @override
  final Iterable<Type> types = const [Scrobbler, _$Scrobbler];

  @override
  final String wireName = r'Scrobbler';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Scrobbler object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'service';
    yield serializers.serialize(
      object.service,
      specifiedType: const FullType(String),
    );
    yield r'available';
    yield serializers.serialize(
      object.available,
      specifiedType: const FullType(bool),
    );
    yield r'connected';
    yield serializers.serialize(
      object.connected,
      specifiedType: const FullType(bool),
    );
    if (object.username != null) {
      yield r'username';
      yield serializers.serialize(
        object.username,
        specifiedType: const FullType(String),
      );
    }
    if (object.apiUrl != null) {
      yield r'apiUrl';
      yield serializers.serialize(
        object.apiUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.lastSuccessAt != null) {
      yield r'lastSuccessAt';
      yield serializers.serialize(
        object.lastSuccessAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.lastError != null) {
      yield r'lastError';
      yield serializers.serialize(
        object.lastError,
        specifiedType: const FullType(String),
      );
    }
    if (object.lastErrorAt != null) {
      yield r'lastErrorAt';
      yield serializers.serialize(
        object.lastErrorAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Scrobbler object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ScrobblerBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'service':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.service = valueDes;
          break;
        case r'available':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.available = valueDes;
          break;
        case r'connected':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.connected = valueDes;
          break;
        case r'username':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.username = valueDes;
          break;
        case r'apiUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.apiUrl = valueDes;
          break;
        case r'lastSuccessAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastSuccessAt = valueDes;
          break;
        case r'lastError':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastError = valueDes;
          break;
        case r'lastErrorAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastErrorAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Scrobbler deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ScrobblerBuilder();
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

