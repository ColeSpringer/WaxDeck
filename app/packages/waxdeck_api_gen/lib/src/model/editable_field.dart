//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'editable_field.g.dart';

/// One editable field or role.
///
/// Properties:
/// * [name] - The field or role name the edit APIs accept.
/// * [writeBack] - Whether the value can write into file tags; false means database-only by upstream design. 
@BuiltValue()
abstract class EditableField implements Built<EditableField, EditableFieldBuilder> {
  /// The field or role name the edit APIs accept.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Whether the value can write into file tags; false means database-only by upstream design. 
  @BuiltValueField(wireName: r'writeBack')
  bool get writeBack;

  EditableField._();

  factory EditableField([void updates(EditableFieldBuilder b)]) = _$EditableField;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EditableFieldBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EditableField> get serializer => _$EditableFieldSerializer();
}

class _$EditableFieldSerializer implements PrimitiveSerializer<EditableField> {
  @override
  final Iterable<Type> types = const [EditableField, _$EditableField];

  @override
  final String wireName = r'EditableField';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EditableField object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'writeBack';
    yield serializers.serialize(
      object.writeBack,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EditableField object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EditableFieldBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'writeBack':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.writeBack = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EditableField deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EditableFieldBuilder();
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

