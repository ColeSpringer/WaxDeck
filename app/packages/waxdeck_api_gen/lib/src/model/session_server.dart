//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'session_server.g.dart';

/// Server-wide state every signed-in account is shown. Present only when authenticated. 
///
/// Properties:
/// * [readOnly] - True while the server is in read-only mode: uploads, edits that write files and deletions are refused for every account. Turning the setting on or off marks every enabled account changed on its sync stream (the `account` event), so a client re-reads the session. 
@BuiltValue()
abstract class SessionServer implements Built<SessionServer, SessionServerBuilder> {
  /// True while the server is in read-only mode: uploads, edits that write files and deletions are refused for every account. Turning the setting on or off marks every enabled account changed on its sync stream (the `account` event), so a client re-reads the session. 
  @BuiltValueField(wireName: r'readOnly')
  bool get readOnly;

  SessionServer._();

  factory SessionServer([void updates(SessionServerBuilder b)]) = _$SessionServer;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SessionServerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SessionServer> get serializer => _$SessionServerSerializer();
}

class _$SessionServerSerializer implements PrimitiveSerializer<SessionServer> {
  @override
  final Iterable<Type> types = const [SessionServer, _$SessionServer];

  @override
  final String wireName = r'SessionServer';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SessionServer object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'readOnly';
    yield serializers.serialize(
      object.readOnly,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SessionServer object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SessionServerBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'readOnly':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.readOnly = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SessionServer deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SessionServerBuilder();
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


