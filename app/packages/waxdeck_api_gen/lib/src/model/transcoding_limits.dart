//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'transcoding_limits.g.dart';

/// Transcode session limits, enforced at the media proxy when a stream engages the streaming engine (direct-played originals never count). 
///
/// Properties:
/// * [maxConcurrent] - Server-wide concurrent transcode session cap; 0 is unlimited (the streaming engine's own admission control remains the backstop). 
/// * [maxConcurrentPerUser] - Per-account concurrent transcode session cap; 0 is unlimited. Administrators are exempt. 
/// * [defaultMaxBitrateKbps] - Default transcode bitrate ceiling in kbit/s for accounts without their own `maxTranscodeKbps`; 0 is unlimited. 
@BuiltValue()
abstract class TranscodingLimits implements Built<TranscodingLimits, TranscodingLimitsBuilder> {
  /// Server-wide concurrent transcode session cap; 0 is unlimited (the streaming engine's own admission control remains the backstop). 
  @BuiltValueField(wireName: r'maxConcurrent')
  int get maxConcurrent;

  /// Per-account concurrent transcode session cap; 0 is unlimited. Administrators are exempt. 
  @BuiltValueField(wireName: r'maxConcurrentPerUser')
  int get maxConcurrentPerUser;

  /// Default transcode bitrate ceiling in kbit/s for accounts without their own `maxTranscodeKbps`; 0 is unlimited. 
  @BuiltValueField(wireName: r'defaultMaxBitrateKbps')
  int get defaultMaxBitrateKbps;

  TranscodingLimits._();

  factory TranscodingLimits([void updates(TranscodingLimitsBuilder b)]) = _$TranscodingLimits;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TranscodingLimitsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TranscodingLimits> get serializer => _$TranscodingLimitsSerializer();
}

class _$TranscodingLimitsSerializer implements PrimitiveSerializer<TranscodingLimits> {
  @override
  final Iterable<Type> types = const [TranscodingLimits, _$TranscodingLimits];

  @override
  final String wireName = r'TranscodingLimits';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TranscodingLimits object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'maxConcurrent';
    yield serializers.serialize(
      object.maxConcurrent,
      specifiedType: const FullType(int),
    );
    yield r'maxConcurrentPerUser';
    yield serializers.serialize(
      object.maxConcurrentPerUser,
      specifiedType: const FullType(int),
    );
    yield r'defaultMaxBitrateKbps';
    yield serializers.serialize(
      object.defaultMaxBitrateKbps,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TranscodingLimits object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TranscodingLimitsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'maxConcurrent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.maxConcurrent = valueDes;
          break;
        case r'maxConcurrentPerUser':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.maxConcurrentPerUser = valueDes;
          break;
        case r'defaultMaxBitrateKbps':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.defaultMaxBitrateKbps = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TranscodingLimits deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TranscodingLimitsBuilder();
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

