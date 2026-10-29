//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/entity_fold.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'entity_fold_page.g.dart';

/// One page of folded names.
///
/// Properties:
/// * [folds] - Folds, ordered by `entityType`, then by `key`.
/// * [nextCursor] - Cursor for the next page, which can come back empty; omitted when no fold can follow. 
@BuiltValue()
abstract class EntityFoldPage implements Built<EntityFoldPage, EntityFoldPageBuilder> {
  /// Folds, ordered by `entityType`, then by `key`.
  @BuiltValueField(wireName: r'folds')
  BuiltList<EntityFold> get folds;

  /// Cursor for the next page, which can come back empty; omitted when no fold can follow. 
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  EntityFoldPage._();

  factory EntityFoldPage([void updates(EntityFoldPageBuilder b)]) = _$EntityFoldPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EntityFoldPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EntityFoldPage> get serializer => _$EntityFoldPageSerializer();
}

class _$EntityFoldPageSerializer implements PrimitiveSerializer<EntityFoldPage> {
  @override
  final Iterable<Type> types = const [EntityFoldPage, _$EntityFoldPage];

  @override
  final String wireName = r'EntityFoldPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EntityFoldPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'folds';
    yield serializers.serialize(
      object.folds,
      specifiedType: const FullType(BuiltList, [FullType(EntityFold)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EntityFoldPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EntityFoldPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'folds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EntityFold)]),
          ) as BuiltList<EntityFold>;
          result.folds.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.nextCursor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EntityFoldPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EntityFoldPageBuilder();
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


