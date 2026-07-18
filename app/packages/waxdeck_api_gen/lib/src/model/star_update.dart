//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'star_update.g.dart';

/// A star or unstar.
///
/// Properties:
/// * [starred] - The new star state.
/// * [recordedAt] - When the change was made on the client, sent only when replaying an offline queue. The server skips the write when the item's star changed more recently than this, so a stale offline toggle never resurrects an undone state. Live mutations omit it and always apply. 
@BuiltValue()
abstract class StarUpdate implements Built<StarUpdate, StarUpdateBuilder> {
  /// The new star state.
  @BuiltValueField(wireName: r'starred')
  bool get starred;

  /// When the change was made on the client, sent only when replaying an offline queue. The server skips the write when the item's star changed more recently than this, so a stale offline toggle never resurrects an undone state. Live mutations omit it and always apply. 
  @BuiltValueField(wireName: r'recordedAt')
  DateTime? get recordedAt;

  StarUpdate._();

  factory StarUpdate([void updates(StarUpdateBuilder b)]) = _$StarUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(StarUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<StarUpdate> get serializer => _$StarUpdateSerializer();
}

class _$StarUpdateSerializer implements PrimitiveSerializer<StarUpdate> {
  @override
  final Iterable<Type> types = const [StarUpdate, _$StarUpdate];

  @override
  final String wireName = r'StarUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    StarUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'starred';
    yield serializers.serialize(
      object.starred,
      specifiedType: const FullType(bool),
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
    StarUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required StarUpdateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'starred':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.starred = valueDes;
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
  StarUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = StarUpdateBuilder();
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

