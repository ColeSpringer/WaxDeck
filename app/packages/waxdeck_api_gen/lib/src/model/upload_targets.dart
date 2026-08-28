//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/upload_target.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upload_targets.g.dart';

/// The libraries a caller may name as an upload target.
///
/// Properties:
/// * [targets] 
@BuiltValue()
abstract class UploadTargets implements Built<UploadTargets, UploadTargetsBuilder> {
  @BuiltValueField(wireName: r'targets')
  BuiltList<UploadTarget> get targets;

  UploadTargets._();

  factory UploadTargets([void updates(UploadTargetsBuilder b)]) = _$UploadTargets;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UploadTargetsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UploadTargets> get serializer => _$UploadTargetsSerializer();
}

class _$UploadTargetsSerializer implements PrimitiveSerializer<UploadTargets> {
  @override
  final Iterable<Type> types = const [UploadTargets, _$UploadTargets];

  @override
  final String wireName = r'UploadTargets';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UploadTargets object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'targets';
    yield serializers.serialize(
      object.targets,
      specifiedType: const FullType(BuiltList, [FullType(UploadTarget)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UploadTargets object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UploadTargetsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'targets':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(UploadTarget)]),
          ) as BuiltList<UploadTarget>;
          result.targets.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UploadTargets deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UploadTargetsBuilder();
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

