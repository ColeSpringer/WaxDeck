//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'metadata_edit.g.dart';

/// Scalar field edits for one item.
///
/// Properties:
/// * [fields] - Field name to new value; an empty string clears the field. Names come from the kind's vocabulary. 
/// * [writeBack] - Also write the new values into the file's tags.
/// * [lock] - Lock the edited fields.
/// * [force] - Override existing locks on the edited fields.
@BuiltValue()
abstract class MetadataEdit implements Built<MetadataEdit, MetadataEditBuilder> {
  /// Field name to new value; an empty string clears the field. Names come from the kind's vocabulary. 
  @BuiltValueField(wireName: r'fields')
  BuiltMap<String, String> get fields;

  /// Also write the new values into the file's tags.
  @BuiltValueField(wireName: r'writeBack')
  bool? get writeBack;

  /// Lock the edited fields.
  @BuiltValueField(wireName: r'lock')
  bool? get lock;

  /// Override existing locks on the edited fields.
  @BuiltValueField(wireName: r'force')
  bool? get force;

  MetadataEdit._();

  factory MetadataEdit([void updates(MetadataEditBuilder b)]) = _$MetadataEdit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MetadataEditBuilder b) => b
      ..writeBack = false
      ..lock = true
      ..force = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<MetadataEdit> get serializer => _$MetadataEditSerializer();
}

class _$MetadataEditSerializer implements PrimitiveSerializer<MetadataEdit> {
  @override
  final Iterable<Type> types = const [MetadataEdit, _$MetadataEdit];

  @override
  final String wireName = r'MetadataEdit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MetadataEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'fields';
    yield serializers.serialize(
      object.fields,
      specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
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
    MetadataEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MetadataEditBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'fields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
          ) as BuiltMap<String, String>;
          result.fields.replace(valueDes);
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
  MetadataEdit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MetadataEditBuilder();
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

