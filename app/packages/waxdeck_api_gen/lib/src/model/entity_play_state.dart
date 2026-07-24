//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'entity_play_state.g.dart';

/// The calling user's star and rating for one catalog entity (an artist or an album). Entities carry no resume position or play count of their own; their items keep those. 
///
/// Properties:
/// * [pid] - The entity this state belongs to.
/// * [starred] - Whether the caller starred the entity.
/// * [starredAt] - When the star was set, which is what orders the starred list. Absent when the entity is not starred. 
/// * [rating] - The caller's rating (0 to 100); absent or null when unrated.
/// * [updatedAt] - When this state last changed.
@BuiltValue()
abstract class EntityPlayState implements Built<EntityPlayState, EntityPlayStateBuilder> {
  /// The entity this state belongs to.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Whether the caller starred the entity.
  @BuiltValueField(wireName: r'starred')
  bool get starred;

  /// When the star was set, which is what orders the starred list. Absent when the entity is not starred. 
  @BuiltValueField(wireName: r'starredAt')
  DateTime? get starredAt;

  /// The caller's rating (0 to 100); absent or null when unrated.
  @BuiltValueField(wireName: r'rating')
  int? get rating;

  /// When this state last changed.
  @BuiltValueField(wireName: r'updatedAt')
  DateTime? get updatedAt;

  EntityPlayState._();

  factory EntityPlayState([void updates(EntityPlayStateBuilder b)]) = _$EntityPlayState;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EntityPlayStateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EntityPlayState> get serializer => _$EntityPlayStateSerializer();
}

class _$EntityPlayStateSerializer implements PrimitiveSerializer<EntityPlayState> {
  @override
  final Iterable<Type> types = const [EntityPlayState, _$EntityPlayState];

  @override
  final String wireName = r'EntityPlayState';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EntityPlayState object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'starred';
    yield serializers.serialize(
      object.starred,
      specifiedType: const FullType(bool),
    );
    if (object.starredAt != null) {
      yield r'starredAt';
      yield serializers.serialize(
        object.starredAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.rating != null) {
      yield r'rating';
      yield serializers.serialize(
        object.rating,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.updatedAt != null) {
      yield r'updatedAt';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EntityPlayState object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EntityPlayStateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'starred':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.starred = valueDes;
          break;
        case r'starredAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.starredAt = valueDes;
          break;
        case r'rating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.rating = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EntityPlayState deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EntityPlayStateBuilder();
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

