//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'credit.g.dart';

/// One credit role with its people.
///
/// Properties:
/// * [role] - The role name.
/// * [names] - The credited people, in stored order.
@BuiltValue()
abstract class Credit implements Built<Credit, CreditBuilder> {
  /// The role name.
  @BuiltValueField(wireName: r'role')
  String get role;

  /// The credited people, in stored order.
  @BuiltValueField(wireName: r'names')
  BuiltList<String> get names;

  Credit._();

  factory Credit([void updates(CreditBuilder b)]) = _$Credit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreditBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Credit> get serializer => _$CreditSerializer();
}

class _$CreditSerializer implements PrimitiveSerializer<Credit> {
  @override
  final Iterable<Type> types = const [Credit, _$Credit];

  @override
  final String wireName = r'Credit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Credit object, {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    Credit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreditBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Credit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreditBuilder();
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

