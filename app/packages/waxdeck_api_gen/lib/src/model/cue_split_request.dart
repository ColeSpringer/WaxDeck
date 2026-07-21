//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cue_split_request.g.dart';

/// Options for a CUE rip split.
///
/// Properties:
/// * [keepOriginals] - Keep the source file and sheet instead of trashing them. 
@BuiltValue()
abstract class CueSplitRequest implements Built<CueSplitRequest, CueSplitRequestBuilder> {
  /// Keep the source file and sheet instead of trashing them. 
  @BuiltValueField(wireName: r'keepOriginals')
  bool? get keepOriginals;

  CueSplitRequest._();

  factory CueSplitRequest([void updates(CueSplitRequestBuilder b)]) = _$CueSplitRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CueSplitRequestBuilder b) => b
      ..keepOriginals = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<CueSplitRequest> get serializer => _$CueSplitRequestSerializer();
}

class _$CueSplitRequestSerializer implements PrimitiveSerializer<CueSplitRequest> {
  @override
  final Iterable<Type> types = const [CueSplitRequest, _$CueSplitRequest];

  @override
  final String wireName = r'CueSplitRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CueSplitRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.keepOriginals != null) {
      yield r'keepOriginals';
      yield serializers.serialize(
        object.keepOriginals,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CueSplitRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CueSplitRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'keepOriginals':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.keepOriginals = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CueSplitRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CueSplitRequestBuilder();
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

