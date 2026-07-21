//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'credits_edit.g.dart';

/// Replacement people for one credit role.
///
/// Properties:
/// * [role] - The role, from the kind's role vocabulary.
/// * [names] - The people; empty clears the role.
/// * [writeBack] - Write the role's tag keys where a form exists.
/// * [lock] - Lock `credit.ROLE`.
/// * [force] - Override an existing lock.
@BuiltValue()
abstract class CreditsEdit implements Built<CreditsEdit, CreditsEditBuilder> {
  /// The role, from the kind's role vocabulary.
  @BuiltValueField(wireName: r'role')
  String get role;

  /// The people; empty clears the role.
  @BuiltValueField(wireName: r'names')
  BuiltList<String> get names;

  /// Write the role's tag keys where a form exists.
  @BuiltValueField(wireName: r'writeBack')
  bool? get writeBack;

  /// Lock `credit.ROLE`.
  @BuiltValueField(wireName: r'lock')
  bool? get lock;

  /// Override an existing lock.
  @BuiltValueField(wireName: r'force')
  bool? get force;

  CreditsEdit._();

  factory CreditsEdit([void updates(CreditsEditBuilder b)]) = _$CreditsEdit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreditsEditBuilder b) => b
      ..writeBack = false
      ..lock = true
      ..force = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreditsEdit> get serializer => _$CreditsEditSerializer();
}

class _$CreditsEditSerializer implements PrimitiveSerializer<CreditsEdit> {
  @override
  final Iterable<Type> types = const [CreditsEdit, _$CreditsEdit];

  @override
  final String wireName = r'CreditsEdit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreditsEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(String),
    );
    yield r'names';
    yield serializers.serialize(
      object.names,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.writeBack != null) {
      yield r'writeBack';
      yield serializers.serialize(
        object.writeBack,
        specifiedType: const FullType(bool),
      );
    }
    if (object.lock != null) {
      yield r'lock';
      yield serializers.serialize(
        object.lock,
        specifiedType: const FullType(bool),
      );
    }
    if (object.force != null) {
      yield r'force';
      yield serializers.serialize(
        object.force,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreditsEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreditsEditBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.role = valueDes;
          break;
        case r'names':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.names.replace(valueDes);
          break;
        case r'writeBack':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.writeBack = valueDes;
          break;
        case r'lock':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.lock = valueDes;
          break;
        case r'force':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.force = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreditsEdit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreditsEditBuilder();
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

