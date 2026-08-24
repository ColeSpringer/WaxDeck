//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item_permissions.g.dart';

/// The caller's permissions on one item.
///
/// Properties:
/// * [mayCurate] - Whether the caller may run the item-scoped metadata mutations: administrators always, everyone else exactly for the items their own uploads brought in. 
@BuiltValue()
abstract class ItemPermissions implements Built<ItemPermissions, ItemPermissionsBuilder> {
  /// Whether the caller may run the item-scoped metadata mutations: administrators always, everyone else exactly for the items their own uploads brought in. 
  @BuiltValueField(wireName: r'mayCurate')
  bool get mayCurate;

  ItemPermissions._();

  factory ItemPermissions([void updates(ItemPermissionsBuilder b)]) = _$ItemPermissions;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ItemPermissionsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ItemPermissions> get serializer => _$ItemPermissionsSerializer();
}

class _$ItemPermissionsSerializer implements PrimitiveSerializer<ItemPermissions> {
  @override
  final Iterable<Type> types = const [ItemPermissions, _$ItemPermissions];

  @override
  final String wireName = r'ItemPermissions';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ItemPermissions object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'mayCurate';
    yield serializers.serialize(
      object.mayCurate,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ItemPermissions object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ItemPermissionsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'mayCurate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.mayCurate = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ItemPermissions deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ItemPermissionsBuilder();
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

