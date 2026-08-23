//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'thumbnail_rung.g.dart';

/// One ladder rung's share of the thumbnail cache.
///
/// Properties:
/// * [size] - The rung in pixels. A requested box is rounded up to one of these, which is what bounds how many derivatives a single cover can accumulate. 
/// * [rows] - Cached thumbnails at this rung.
/// * [bytes] - What they cost.
@BuiltValue()
abstract class ThumbnailRung implements Built<ThumbnailRung, ThumbnailRungBuilder> {
  /// The rung in pixels. A requested box is rounded up to one of these, which is what bounds how many derivatives a single cover can accumulate. 
  @BuiltValueField(wireName: r'size')
  int get size;

  /// Cached thumbnails at this rung.
  @BuiltValueField(wireName: r'rows')
  int get rows;

  /// What they cost.
  @BuiltValueField(wireName: r'bytes')
  int get bytes;

  ThumbnailRung._();

  factory ThumbnailRung([void updates(ThumbnailRungBuilder b)]) = _$ThumbnailRung;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ThumbnailRungBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ThumbnailRung> get serializer => _$ThumbnailRungSerializer();
}

class _$ThumbnailRungSerializer implements PrimitiveSerializer<ThumbnailRung> {
  @override
  final Iterable<Type> types = const [ThumbnailRung, _$ThumbnailRung];

  @override
  final String wireName = r'ThumbnailRung';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ThumbnailRung object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'size';
    yield serializers.serialize(
      object.size,
      specifiedType: const FullType(int),
    );
    yield r'rows';
    yield serializers.serialize(
      object.rows,
      specifiedType: const FullType(int),
    );
    yield r'bytes';
    yield serializers.serialize(
      object.bytes,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ThumbnailRung object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ThumbnailRungBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'size':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.size = valueDes;
          break;
        case r'rows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.rows = valueDes;
          break;
        case r'bytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ThumbnailRung deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ThumbnailRungBuilder();
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

