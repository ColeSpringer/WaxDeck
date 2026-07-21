//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'duplicate_entity.g.dart';

/// One entity in a duplicate group.
///
/// Properties:
/// * [pid] - The entity.
/// * [name] - Its display name.
/// * [itemCount] - Items under the entity, when cheaply known.
@BuiltValue()
abstract class DuplicateEntity implements Built<DuplicateEntity, DuplicateEntityBuilder> {
  /// The entity.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Its display name.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Items under the entity, when cheaply known.
  @BuiltValueField(wireName: r'itemCount')
  int? get itemCount;

  DuplicateEntity._();

  factory DuplicateEntity([void updates(DuplicateEntityBuilder b)]) = _$DuplicateEntity;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DuplicateEntityBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DuplicateEntity> get serializer => _$DuplicateEntitySerializer();
}

class _$DuplicateEntitySerializer implements PrimitiveSerializer<DuplicateEntity> {
  @override
  final Iterable<Type> types = const [DuplicateEntity, _$DuplicateEntity];

  @override
  final String wireName = r'DuplicateEntity';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DuplicateEntity object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.itemCount != null) {
      yield r'itemCount';
      yield serializers.serialize(
        object.itemCount,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DuplicateEntity object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DuplicateEntityBuilder result,
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
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'itemCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.itemCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DuplicateEntity deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DuplicateEntityBuilder();
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

