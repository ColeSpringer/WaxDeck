//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'release_status_edit.g.dart';

/// The unofficial mark.
///
/// Properties:
/// * [unofficial] - True marks the item as having no canonical release; false clears the mark. 
@BuiltValue()
abstract class ReleaseStatusEdit implements Built<ReleaseStatusEdit, ReleaseStatusEditBuilder> {
  /// True marks the item as having no canonical release; false clears the mark. 
  @BuiltValueField(wireName: r'unofficial')
  bool get unofficial;

  ReleaseStatusEdit._();

  factory ReleaseStatusEdit([void updates(ReleaseStatusEditBuilder b)]) = _$ReleaseStatusEdit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReleaseStatusEditBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReleaseStatusEdit> get serializer => _$ReleaseStatusEditSerializer();
}

class _$ReleaseStatusEditSerializer implements PrimitiveSerializer<ReleaseStatusEdit> {
  @override
  final Iterable<Type> types = const [ReleaseStatusEdit, _$ReleaseStatusEdit];

  @override
  final String wireName = r'ReleaseStatusEdit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReleaseStatusEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'unofficial';
    yield serializers.serialize(
      object.unofficial,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ReleaseStatusEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReleaseStatusEditBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'unofficial':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.unofficial = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReleaseStatusEdit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReleaseStatusEditBuilder();
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

