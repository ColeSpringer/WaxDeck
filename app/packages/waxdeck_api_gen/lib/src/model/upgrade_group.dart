//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/upgrade_member.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upgrade_group.g.dart';

/// One recording's encodings.
///
/// Properties:
/// * [members] - The encodings, best first.
@BuiltValue()
abstract class UpgradeGroup implements Built<UpgradeGroup, UpgradeGroupBuilder> {
  /// The encodings, best first.
  @BuiltValueField(wireName: r'members')
  BuiltList<UpgradeMember> get members;

  UpgradeGroup._();

  factory UpgradeGroup([void updates(UpgradeGroupBuilder b)]) = _$UpgradeGroup;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpgradeGroupBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpgradeGroup> get serializer => _$UpgradeGroupSerializer();
}

class _$UpgradeGroupSerializer implements PrimitiveSerializer<UpgradeGroup> {
  @override
  final Iterable<Type> types = const [UpgradeGroup, _$UpgradeGroup];

  @override
  final String wireName = r'UpgradeGroup';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpgradeGroup object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'members';
    yield serializers.serialize(
      object.members,
      specifiedType: const FullType(BuiltList, [FullType(UpgradeMember)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UpgradeGroup object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpgradeGroupBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'members':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(UpgradeMember)]),
          ) as BuiltList<UpgradeMember>;
          result.members.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpgradeGroup deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpgradeGroupBuilder();
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

