//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'lastfm_connect_start.g.dart';

/// The Last.fm authorization hand-off.
///
/// Properties:
/// * [authUrl] - The Last.fm authorization URL to open in a browser; it redirects back to this server's callback on approval. 
@BuiltValue()
abstract class LastfmConnectStart implements Built<LastfmConnectStart, LastfmConnectStartBuilder> {
  /// The Last.fm authorization URL to open in a browser; it redirects back to this server's callback on approval. 
  @BuiltValueField(wireName: r'authUrl')
  String get authUrl;

  LastfmConnectStart._();

  factory LastfmConnectStart([void updates(LastfmConnectStartBuilder b)]) = _$LastfmConnectStart;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LastfmConnectStartBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LastfmConnectStart> get serializer => _$LastfmConnectStartSerializer();
}

class _$LastfmConnectStartSerializer implements PrimitiveSerializer<LastfmConnectStart> {
  @override
  final Iterable<Type> types = const [LastfmConnectStart, _$LastfmConnectStart];

  @override
  final String wireName = r'LastfmConnectStart';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LastfmConnectStart object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'authUrl';
    yield serializers.serialize(
      object.authUrl,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LastfmConnectStart object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LastfmConnectStartBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'authUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.authUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LastfmConnectStart deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LastfmConnectStartBuilder();
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

