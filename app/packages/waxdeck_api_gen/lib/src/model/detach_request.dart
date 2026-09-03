//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'detach_request.g.dart';

/// A per-member detach.
///
/// Properties:
/// * [writeBack] - Also strip the two MusicBrainz release tags from the track's file. 
@BuiltValue()
abstract class DetachRequest implements Built<DetachRequest, DetachRequestBuilder> {
  /// Also strip the two MusicBrainz release tags from the track's file. 
  @BuiltValueField(wireName: r'writeBack')
  bool? get writeBack;

  DetachRequest._();

  factory DetachRequest([void updates(DetachRequestBuilder b)]) = _$DetachRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DetachRequestBuilder b) => b
      ..writeBack = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<DetachRequest> get serializer => _$DetachRequestSerializer();
}

class _$DetachRequestSerializer implements PrimitiveSerializer<DetachRequest> {
  @override
  final Iterable<Type> types = const [DetachRequest, _$DetachRequest];

  @override
  final String wireName = r'DetachRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DetachRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.writeBack != null) {
      yield r'writeBack';
      yield serializers.serialize(
        object.writeBack,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DetachRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DetachRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'writeBack':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.writeBack = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DetachRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DetachRequestBuilder();
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

