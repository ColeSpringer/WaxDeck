//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_failure.g.dart';

/// One file organize could not move.
///
/// Properties:
/// * [path] - The file.
/// * [reason] - Why it did not move.
@BuiltValue()
abstract class OrganizeFailure implements Built<OrganizeFailure, OrganizeFailureBuilder> {
  /// The file.
  @BuiltValueField(wireName: r'path')
  String get path;

  /// Why it did not move.
  @BuiltValueField(wireName: r'reason')
  String get reason;

  OrganizeFailure._();

  factory OrganizeFailure([void updates(OrganizeFailureBuilder b)]) = _$OrganizeFailure;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeFailureBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeFailure> get serializer => _$OrganizeFailureSerializer();
}

class _$OrganizeFailureSerializer implements PrimitiveSerializer<OrganizeFailure> {
  @override
  final Iterable<Type> types = const [OrganizeFailure, _$OrganizeFailure];

  @override
  final String wireName = r'OrganizeFailure';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeFailure object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OrganizeFailure object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeFailureBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.path = valueDes;
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrganizeFailure deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeFailureBuilder();
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

