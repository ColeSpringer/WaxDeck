//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/duplicate_group.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'duplicate_groups.g.dart';

/// Duplicate entity groups from the audit.
///
/// Properties:
/// * [groups] - Groups, bounded to the first two hundred.
@BuiltValue()
abstract class DuplicateGroups implements Built<DuplicateGroups, DuplicateGroupsBuilder> {
  /// Groups, bounded to the first two hundred.
  @BuiltValueField(wireName: r'groups')
  BuiltList<DuplicateGroup> get groups;

  DuplicateGroups._();

  factory DuplicateGroups([void updates(DuplicateGroupsBuilder b)]) = _$DuplicateGroups;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DuplicateGroupsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DuplicateGroups> get serializer => _$DuplicateGroupsSerializer();
}

class _$DuplicateGroupsSerializer implements PrimitiveSerializer<DuplicateGroups> {
  @override
  final Iterable<Type> types = const [DuplicateGroups, _$DuplicateGroups];

  @override
  final String wireName = r'DuplicateGroups';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DuplicateGroups object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'groups';
    yield serializers.serialize(
      object.groups,
      specifiedType: const FullType(BuiltList, [FullType(DuplicateGroup)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DuplicateGroups object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DuplicateGroupsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'groups':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DuplicateGroup)]),
          ) as BuiltList<DuplicateGroup>;
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
  DuplicateGroups deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DuplicateGroupsBuilder();
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

