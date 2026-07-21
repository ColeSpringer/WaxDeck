//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upgrade_resolve_result.g.dart';

/// The resolution outcome.
///
/// Properties:
/// * [trashed] - Items moved to the trash.
@BuiltValue()
abstract class UpgradeResolveResult implements Built<UpgradeResolveResult, UpgradeResolveResultBuilder> {
  /// Items moved to the trash.
  @BuiltValueField(wireName: r'trashed')
  int get trashed;

  UpgradeResolveResult._();

  factory UpgradeResolveResult([void updates(UpgradeResolveResultBuilder b)]) = _$UpgradeResolveResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpgradeResolveResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpgradeResolveResult> get serializer => _$UpgradeResolveResultSerializer();
}

class _$UpgradeResolveResultSerializer implements PrimitiveSerializer<UpgradeResolveResult> {
  @override
  final Iterable<Type> types = const [UpgradeResolveResult, _$UpgradeResolveResult];

  @override
  final String wireName = r'UpgradeResolveResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpgradeResolveResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'trashed';
    yield serializers.serialize(
      object.trashed,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UpgradeResolveResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpgradeResolveResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'trashed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.trashed = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpgradeResolveResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpgradeResolveResultBuilder();
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

