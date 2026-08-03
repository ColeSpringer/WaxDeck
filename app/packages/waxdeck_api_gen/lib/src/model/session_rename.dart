//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'session_rename.g.dart';

/// A new label for one session in the device list.
///
/// Properties:
/// * [deviceName] - Human-readable label for this session (for example `Pixel 9` or `Study desktop`), matching what a login may supply. Trimmed of surrounding whitespace; empty after trimming is `invalid-request`. 
@BuiltValue()
abstract class SessionRename implements Built<SessionRename, SessionRenameBuilder> {
  /// Human-readable label for this session (for example `Pixel 9` or `Study desktop`), matching what a login may supply. Trimmed of surrounding whitespace; empty after trimming is `invalid-request`. 
  @BuiltValueField(wireName: r'deviceName')
  String get deviceName;

  SessionRename._();

  factory SessionRename([void updates(SessionRenameBuilder b)]) = _$SessionRename;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SessionRenameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SessionRename> get serializer => _$SessionRenameSerializer();
}

class _$SessionRenameSerializer implements PrimitiveSerializer<SessionRename> {
  @override
  final Iterable<Type> types = const [SessionRename, _$SessionRename];

  @override
  final String wireName = r'SessionRename';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SessionRename object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'deviceName';
    yield serializers.serialize(
      object.deviceName,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SessionRename object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SessionRenameBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
  SessionRename deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SessionRenameBuilder();
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

