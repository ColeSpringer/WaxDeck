//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/cast_preflight_base.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cast_preflight.g.dart';

/// The advertise bases cast sessions will offer, in try order, each with a server-side reachability verdict. 
///
/// Properties:
/// * [bases] 
@BuiltValue()
abstract class CastPreflight implements Built<CastPreflight, CastPreflightBuilder> {
  @BuiltValueField(wireName: r'bases')
  BuiltList<CastPreflightBase> get bases;

  CastPreflight._();

  factory CastPreflight([void updates(CastPreflightBuilder b)]) = _$CastPreflight;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CastPreflightBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CastPreflight> get serializer => _$CastPreflightSerializer();
}

class _$CastPreflightSerializer implements PrimitiveSerializer<CastPreflight> {
  @override
  final Iterable<Type> types = const [CastPreflight, _$CastPreflight];

  @override
  final String wireName = r'CastPreflight';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CastPreflight object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'bases';
    yield serializers.serialize(
      object.bases,
      specifiedType: const FullType(BuiltList, [FullType(CastPreflightBase)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CastPreflight object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CastPreflightBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'bases':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(CastPreflightBase)]),
          ) as BuiltList<CastPreflightBase>;
          result.bases.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CastPreflight deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CastPreflightBuilder();
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

