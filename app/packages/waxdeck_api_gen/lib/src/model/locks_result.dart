//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'locks_result.g.dart';

/// The item's locks after the change.
///
/// Properties:
/// * [lockedFields] - Every currently locked field.
@BuiltValue()
abstract class LocksResult implements Built<LocksResult, LocksResultBuilder> {
  /// Every currently locked field.
  @BuiltValueField(wireName: r'lockedFields')
  BuiltList<String> get lockedFields;

  LocksResult._();

  factory LocksResult([void updates(LocksResultBuilder b)]) = _$LocksResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LocksResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LocksResult> get serializer => _$LocksResultSerializer();
}

class _$LocksResultSerializer implements PrimitiveSerializer<LocksResult> {
  @override
  final Iterable<Type> types = const [LocksResult, _$LocksResult];

  @override
  final String wireName = r'LocksResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LocksResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'lockedFields';
    yield serializers.serialize(
      object.lockedFields,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LocksResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LocksResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'lockedFields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.lockedFields.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LocksResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LocksResultBuilder();
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

