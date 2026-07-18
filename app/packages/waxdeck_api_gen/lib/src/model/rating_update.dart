//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rating_update.g.dart';

/// A rating change.
///
/// Properties:
/// * [rating] - The new rating (0 to 100), or null to clear it.
/// * [recordedAt] - When the change was made on the client, sent only when replaying an offline queue. The server skips the write when the item's rating changed more recently than this. Live mutations omit it and always apply. 
@BuiltValue()
abstract class RatingUpdate implements Built<RatingUpdate, RatingUpdateBuilder> {
  /// The new rating (0 to 100), or null to clear it.
  @BuiltValueField(wireName: r'rating')
  int? get rating;

  /// When the change was made on the client, sent only when replaying an offline queue. The server skips the write when the item's rating changed more recently than this. Live mutations omit it and always apply. 
  @BuiltValueField(wireName: r'recordedAt')
  DateTime? get recordedAt;

  RatingUpdate._();

  factory RatingUpdate([void updates(RatingUpdateBuilder b)]) = _$RatingUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RatingUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RatingUpdate> get serializer => _$RatingUpdateSerializer();
}

class _$RatingUpdateSerializer implements PrimitiveSerializer<RatingUpdate> {
  @override
  final Iterable<Type> types = const [RatingUpdate, _$RatingUpdate];

  @override
  final String wireName = r'RatingUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RatingUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'rating';
    yield object.rating == null ? null : serializers.serialize(
      object.rating,
      specifiedType: const FullType.nullable(int),
    );
    if (object.recordedAt != null) {
      yield r'recordedAt';
      yield serializers.serialize(
        object.recordedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RatingUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RatingUpdateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'rating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.rating = valueDes;
          break;
        case r'recordedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.recordedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RatingUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RatingUpdateBuilder();
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

