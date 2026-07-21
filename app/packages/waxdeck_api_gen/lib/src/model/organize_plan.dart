//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/organize_action.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_plan.g.dart';

/// A dry-run organize plan.
///
/// Properties:
/// * [profile] - The profile planned with.
/// * [totalActions] - Moves the pass would make in total.
/// * [actions] - The first five hundred actions.
/// * [tagWrite] - Whether applying would also write tags.
@BuiltValue()
abstract class OrganizePlan implements Built<OrganizePlan, OrganizePlanBuilder> {
  /// The profile planned with.
  @BuiltValueField(wireName: r'profile')
  String get profile;

  /// Moves the pass would make in total.
  @BuiltValueField(wireName: r'totalActions')
  int get totalActions;

  /// The first five hundred actions.
  @BuiltValueField(wireName: r'actions')
  BuiltList<OrganizeAction> get actions;

  /// Whether applying would also write tags.
  @BuiltValueField(wireName: r'tagWrite')
  bool? get tagWrite;

  OrganizePlan._();

  factory OrganizePlan([void updates(OrganizePlanBuilder b)]) = _$OrganizePlan;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizePlanBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizePlan> get serializer => _$OrganizePlanSerializer();
}

class _$OrganizePlanSerializer implements PrimitiveSerializer<OrganizePlan> {
  @override
  final Iterable<Type> types = const [OrganizePlan, _$OrganizePlan];

  @override
  final String wireName = r'OrganizePlan';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizePlan object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'profile';
    yield serializers.serialize(
      object.profile,
      specifiedType: const FullType(String),
    );
    yield r'totalActions';
    yield serializers.serialize(
      object.totalActions,
      specifiedType: const FullType(int),
    );
    yield r'actions';
    yield serializers.serialize(
      object.actions,
      specifiedType: const FullType(BuiltList, [FullType(OrganizeAction)]),
    );
    if (object.tagWrite != null) {
      yield r'tagWrite';
      yield serializers.serialize(
        object.tagWrite,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OrganizePlan object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizePlanBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'profile':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.profile = valueDes;
          break;
        case r'totalActions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalActions = valueDes;
          break;
        case r'actions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(OrganizeAction)]),
          ) as BuiltList<OrganizeAction>;
          result.actions.replace(valueDes);
          break;
        case r'tagWrite':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.tagWrite = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrganizePlan deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizePlanBuilder();
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

