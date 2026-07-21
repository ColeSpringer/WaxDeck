//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/upgrade_group.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upgrade_groups.g.dart';

/// Same-recording different-encoding groups.
///
/// Properties:
/// * [groups] - Groups, best quality first within each.
@BuiltValue()
abstract class UpgradeGroups implements Built<UpgradeGroups, UpgradeGroupsBuilder> {
  /// Groups, best quality first within each.
  @BuiltValueField(wireName: r'groups')
  BuiltList<UpgradeGroup> get groups;

  UpgradeGroups._();

  factory UpgradeGroups([void updates(UpgradeGroupsBuilder b)]) = _$UpgradeGroups;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpgradeGroupsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpgradeGroups> get serializer => _$UpgradeGroupsSerializer();
}

class _$UpgradeGroupsSerializer implements PrimitiveSerializer<UpgradeGroups> {
  @override
  final Iterable<Type> types = const [UpgradeGroups, _$UpgradeGroups];

  @override
  final String wireName = r'UpgradeGroups';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpgradeGroups object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'groups';
    yield serializers.serialize(
      object.groups,
      specifiedType: const FullType(BuiltList, [FullType(UpgradeGroup)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UpgradeGroups object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpgradeGroupsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'groups':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(UpgradeGroup)]),
          ) as BuiltList<UpgradeGroup>;
          result.groups.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpgradeGroups deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpgradeGroupsBuilder();
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

