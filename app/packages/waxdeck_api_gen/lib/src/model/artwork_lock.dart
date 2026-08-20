//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'artwork_lock.g.dart';

/// Whether an entity's front cover is pinned against enrichment and scan re-derives. 
///
/// Properties:
/// * [locked] - True when the cover is pinned.
@BuiltValue()
abstract class ArtworkLock implements Built<ArtworkLock, ArtworkLockBuilder> {
  /// True when the cover is pinned.
  @BuiltValueField(wireName: r'locked')
  bool get locked;

  ArtworkLock._();

  factory ArtworkLock([void updates(ArtworkLockBuilder b)]) = _$ArtworkLock;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ArtworkLockBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ArtworkLock> get serializer => _$ArtworkLockSerializer();
}

class _$ArtworkLockSerializer implements PrimitiveSerializer<ArtworkLock> {
  @override
  final Iterable<Type> types = const [ArtworkLock, _$ArtworkLock];

  @override
  final String wireName = r'ArtworkLock';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ArtworkLock object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'locked';
    yield serializers.serialize(
      object.locked,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ArtworkLock object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ArtworkLockBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'locked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.locked = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ArtworkLock deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ArtworkLockBuilder();
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

