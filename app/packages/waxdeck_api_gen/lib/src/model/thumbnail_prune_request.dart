//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'thumbnail_prune_request.g.dart';

/// Which cached thumbnails to drop. Both bounds are optional and an absent one leaves that axis unbounded, but at least one must be given - a request with neither is refused rather than read as \"everything\". Zero is a value, not an absence: `olderThanSeconds: 0` drops every entry, and `maxBytes: 0` evicts the cache entirely. 
///
/// Properties:
/// * [olderThanSeconds] - Drop entries generated at least this long ago. Absent leaves the age unbounded. 
/// * [maxBytes] - Evict oldest-first until the cache fits this many bytes. Absent leaves the size unbounded. 
@BuiltValue()
abstract class ThumbnailPruneRequest implements Built<ThumbnailPruneRequest, ThumbnailPruneRequestBuilder> {
  /// Drop entries generated at least this long ago. Absent leaves the age unbounded. 
  @BuiltValueField(wireName: r'olderThanSeconds')
  int? get olderThanSeconds;

  /// Evict oldest-first until the cache fits this many bytes. Absent leaves the size unbounded. 
  @BuiltValueField(wireName: r'maxBytes')
  int? get maxBytes;

  ThumbnailPruneRequest._();

  factory ThumbnailPruneRequest([void updates(ThumbnailPruneRequestBuilder b)]) = _$ThumbnailPruneRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ThumbnailPruneRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ThumbnailPruneRequest> get serializer => _$ThumbnailPruneRequestSerializer();
}

class _$ThumbnailPruneRequestSerializer implements PrimitiveSerializer<ThumbnailPruneRequest> {
  @override
  final Iterable<Type> types = const [ThumbnailPruneRequest, _$ThumbnailPruneRequest];

  @override
  final String wireName = r'ThumbnailPruneRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ThumbnailPruneRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.olderThanSeconds != null) {
      yield r'olderThanSeconds';
      yield serializers.serialize(
        object.olderThanSeconds,
        specifiedType: const FullType(int),
      );
    }
    if (object.maxBytes != null) {
      yield r'maxBytes';
      yield serializers.serialize(
        object.maxBytes,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ThumbnailPruneRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ThumbnailPruneRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'olderThanSeconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.olderThanSeconds = valueDes;
          break;
        case r'maxBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.maxBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ThumbnailPruneRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ThumbnailPruneRequestBuilder();
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

