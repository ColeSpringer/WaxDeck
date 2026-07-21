//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_action.g.dart';

/// One planned move.
///
/// Properties:
/// * [itemPid] - The item whose file moves.
/// * [from] - Current library-relative path.
/// * [to] - Planned library-relative path.
@BuiltValue()
abstract class OrganizeAction implements Built<OrganizeAction, OrganizeActionBuilder> {
  /// The item whose file moves.
  @BuiltValueField(wireName: r'itemPid')
  String get itemPid;

  /// Current library-relative path.
  @BuiltValueField(wireName: r'from')
  String get from;

  /// Planned library-relative path.
  @BuiltValueField(wireName: r'to')
  String get to;

  OrganizeAction._();

  factory OrganizeAction([void updates(OrganizeActionBuilder b)]) = _$OrganizeAction;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeActionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeAction> get serializer => _$OrganizeActionSerializer();
}

class _$OrganizeActionSerializer implements PrimitiveSerializer<OrganizeAction> {
  @override
  final Iterable<Type> types = const [OrganizeAction, _$OrganizeAction];

  @override
  final String wireName = r'OrganizeAction';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeAction object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'itemPid';
    yield serializers.serialize(
      object.itemPid,
      specifiedType: const FullType(String),
    );
    yield r'from';
    yield serializers.serialize(
      object.from,
      specifiedType: const FullType(String),
    );
    yield r'to';
    yield serializers.serialize(
      object.to,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OrganizeAction object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeActionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'itemPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.itemPid = valueDes;
          break;
        case r'from':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.from = valueDes;
          break;
        case r'to':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.to = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrganizeAction deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeActionBuilder();
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

