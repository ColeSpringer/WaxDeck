//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_fix_request.g.dart';

/// A bulk fix for one rule.
///
/// Properties:
/// * [rule] - The rule to fix.
/// * [itemPids] - Restrict to these items; absent fixes everything currently failing the rule. 
@BuiltValue()
abstract class HealthFixRequest implements Built<HealthFixRequest, HealthFixRequestBuilder> {
  /// The rule to fix.
  @BuiltValueField(wireName: r'rule')
  String get rule;

  /// Restrict to these items; absent fixes everything currently failing the rule. 
  @BuiltValueField(wireName: r'itemPids')
  BuiltList<String>? get itemPids;

  HealthFixRequest._();

  factory HealthFixRequest([void updates(HealthFixRequestBuilder b)]) = _$HealthFixRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthFixRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthFixRequest> get serializer => _$HealthFixRequestSerializer();
}

class _$HealthFixRequestSerializer implements PrimitiveSerializer<HealthFixRequest> {
  @override
  final Iterable<Type> types = const [HealthFixRequest, _$HealthFixRequest];

  @override
  final String wireName = r'HealthFixRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthFixRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'rule';
    yield serializers.serialize(
      object.rule,
      specifiedType: const FullType(String),
    );
    if (object.itemPids != null) {
      yield r'itemPids';
      yield serializers.serialize(
        object.itemPids,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    HealthFixRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HealthFixRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'rule':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.rule = valueDes;
          break;
        case r'itemPids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.itemPids.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HealthFixRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthFixRequestBuilder();
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

