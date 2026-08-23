//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'thumbnail_prune_result.g.dart';

/// What a thumbnail-cache prune dropped.
///
/// Properties:
/// * [removed] - Cached thumbnails dropped.
/// * [freedBytes] - What they held. Freed inside the catalog file rather than returned to the filesystem. 
@BuiltValue()
abstract class ThumbnailPruneResult implements Built<ThumbnailPruneResult, ThumbnailPruneResultBuilder> {
  /// Cached thumbnails dropped.
  @BuiltValueField(wireName: r'removed')
  int get removed;

  /// What they held. Freed inside the catalog file rather than returned to the filesystem. 
  @BuiltValueField(wireName: r'freedBytes')
  int get freedBytes;

  ThumbnailPruneResult._();

  factory ThumbnailPruneResult([void updates(ThumbnailPruneResultBuilder b)]) = _$ThumbnailPruneResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ThumbnailPruneResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ThumbnailPruneResult> get serializer => _$ThumbnailPruneResultSerializer();
}

class _$ThumbnailPruneResultSerializer implements PrimitiveSerializer<ThumbnailPruneResult> {
  @override
  final Iterable<Type> types = const [ThumbnailPruneResult, _$ThumbnailPruneResult];

  @override
  final String wireName = r'ThumbnailPruneResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ThumbnailPruneResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'removed';
    yield serializers.serialize(
      object.removed,
      specifiedType: const FullType(int),
    );
    yield r'freedBytes';
    yield serializers.serialize(
      object.freedBytes,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ThumbnailPruneResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ThumbnailPruneResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'removed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.removed = valueDes;
          break;
        case r'freedBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.freedBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ThumbnailPruneResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ThumbnailPruneResultBuilder();
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

