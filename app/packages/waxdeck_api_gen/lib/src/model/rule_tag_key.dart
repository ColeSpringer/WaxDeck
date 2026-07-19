//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rule_tag_key.g.dart';

/// One custom tag key usable as a `tag.KEY` field.
///
/// Properties:
/// * [key] - Canonical tag key; address it as `tag.KEY`.
/// * [itemCount] - Distinct items carrying this key.
@BuiltValue()
abstract class RuleTagKey implements Built<RuleTagKey, RuleTagKeyBuilder> {
  /// Canonical tag key; address it as `tag.KEY`.
  @BuiltValueField(wireName: r'key')
  String get key;

  /// Distinct items carrying this key.
  @BuiltValueField(wireName: r'itemCount')
  int get itemCount;

  RuleTagKey._();

  factory RuleTagKey([void updates(RuleTagKeyBuilder b)]) = _$RuleTagKey;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RuleTagKeyBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RuleTagKey> get serializer => _$RuleTagKeySerializer();
}

class _$RuleTagKeySerializer implements PrimitiveSerializer<RuleTagKey> {
  @override
  final Iterable<Type> types = const [RuleTagKey, _$RuleTagKey];

  @override
  final String wireName = r'RuleTagKey';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RuleTagKey object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'key';
    yield serializers.serialize(
      object.key,
      specifiedType: const FullType(String),
    );
    yield r'itemCount';
    yield serializers.serialize(
      object.itemCount,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RuleTagKey object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RuleTagKeyBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.key = valueDes;
          break;
        case r'itemCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.itemCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RuleTagKey deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RuleTagKeyBuilder();
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

