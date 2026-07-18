//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bootstrap_status.g.dart';

/// Whether first-run setup is still waiting for an administrator.
///
/// Properties:
/// * [required_] - True while the server has no enabled administrator.
@BuiltValue()
abstract class BootstrapStatus implements Built<BootstrapStatus, BootstrapStatusBuilder> {
  /// True while the server has no enabled administrator.
  @BuiltValueField(wireName: r'required')
  bool get required_;

  BootstrapStatus._();

  factory BootstrapStatus([void updates(BootstrapStatusBuilder b)]) = _$BootstrapStatus;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BootstrapStatusBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BootstrapStatus> get serializer => _$BootstrapStatusSerializer();
}

class _$BootstrapStatusSerializer implements PrimitiveSerializer<BootstrapStatus> {
  @override
  final Iterable<Type> types = const [BootstrapStatus, _$BootstrapStatus];

  @override
  final String wireName = r'BootstrapStatus';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BootstrapStatus object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'required';
    yield serializers.serialize(
      object.required_,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    BootstrapStatus object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BootstrapStatusBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'required':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.required_ = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BootstrapStatus deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BootstrapStatusBuilder();
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

