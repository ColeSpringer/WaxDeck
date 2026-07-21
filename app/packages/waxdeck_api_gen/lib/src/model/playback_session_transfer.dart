//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playback_session_transfer.g.dart';

/// Move a session's live playback to another endpoint.
///
/// Properties:
/// * [endpointId] - The endpoint to move playback to.
@BuiltValue()
abstract class PlaybackSessionTransfer implements Built<PlaybackSessionTransfer, PlaybackSessionTransferBuilder> {
  /// The endpoint to move playback to.
  @BuiltValueField(wireName: r'endpointId')
  String get endpointId;

  PlaybackSessionTransfer._();

  factory PlaybackSessionTransfer([void updates(PlaybackSessionTransferBuilder b)]) = _$PlaybackSessionTransfer;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaybackSessionTransferBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaybackSessionTransfer> get serializer => _$PlaybackSessionTransferSerializer();
}

class _$PlaybackSessionTransferSerializer implements PrimitiveSerializer<PlaybackSessionTransfer> {
  @override
  final Iterable<Type> types = const [PlaybackSessionTransfer, _$PlaybackSessionTransfer];

  @override
  final String wireName = r'PlaybackSessionTransfer';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaybackSessionTransfer object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'endpointId';
    yield serializers.serialize(
      object.endpointId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaybackSessionTransfer object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaybackSessionTransferBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'endpointId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.endpointId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaybackSessionTransfer deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaybackSessionTransferBuilder();
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

