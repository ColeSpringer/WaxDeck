//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'locks_edit.g.dart';

/// A lock or unlock for named fields.
///
/// Properties:
/// * [fields] - The fields, possibly namespaced.
/// * [locked] - True locks, false unlocks.
@BuiltValue()
abstract class LocksEdit implements Built<LocksEdit, LocksEditBuilder> {
  /// The fields, possibly namespaced.
  @BuiltValueField(wireName: r'fields')
  BuiltList<String> get fields;

  /// True locks, false unlocks.
  @BuiltValueField(wireName: r'locked')
  bool get locked;

  LocksEdit._();

  factory LocksEdit([void updates(LocksEditBuilder b)]) = _$LocksEdit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LocksEditBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LocksEdit> get serializer => _$LocksEditSerializer();
}

class _$LocksEditSerializer implements PrimitiveSerializer<LocksEdit> {
  @override
  final Iterable<Type> types = const [LocksEdit, _$LocksEdit];

  @override
  final String wireName = r'LocksEdit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LocksEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'fields';
    yield serializers.serialize(
      object.fields,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'locked';
    yield serializers.serialize(
      object.locked,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LocksEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LocksEditBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'fields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.fields.replace(valueDes);
          break;
        case r'locked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.locked = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LocksEdit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LocksEditBuilder();
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

