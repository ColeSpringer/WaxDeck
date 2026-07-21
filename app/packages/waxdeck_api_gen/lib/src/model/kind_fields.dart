//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/editable_field.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'kind_fields.g.dart';

/// One item kind's editable vocabulary.
///
/// Properties:
/// * [kind] 
/// * [fields] - Editable scalar fields.
/// * [creditRoles] - Credit roles for the kind; roles marked database-only have no round-trippable tag form. 
@BuiltValue()
abstract class KindFields implements Built<KindFields, KindFieldsBuilder> {
  @BuiltValueField(wireName: r'kind')
  MediaType get kind;
  // enum kindEnum {  music,  podcast,  audiobook,  };

  /// Editable scalar fields.
  @BuiltValueField(wireName: r'fields')
  BuiltList<EditableField> get fields;

  /// Credit roles for the kind; roles marked database-only have no round-trippable tag form. 
  @BuiltValueField(wireName: r'creditRoles')
  BuiltList<EditableField> get creditRoles;

  KindFields._();

  factory KindFields([void updates(KindFieldsBuilder b)]) = _$KindFields;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(KindFieldsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<KindFields> get serializer => _$KindFieldsSerializer();
}

class _$KindFieldsSerializer implements PrimitiveSerializer<KindFields> {
  @override
  final Iterable<Type> types = const [KindFields, _$KindFields];

  @override
  final String wireName = r'KindFields';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    KindFields object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(MediaType),
    );
    yield r'fields';
    yield serializers.serialize(
      object.fields,
      specifiedType: const FullType(BuiltList, [FullType(EditableField)]),
    );
    yield r'creditRoles';
    yield serializers.serialize(
      object.creditRoles,
      specifiedType: const FullType(BuiltList, [FullType(EditableField)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    KindFields object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required KindFieldsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaType),
          ) as MediaType;
          result.kind = valueDes;
          break;
        case r'fields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EditableField)]),
          ) as BuiltList<EditableField>;
          result.fields.replace(valueDes);
          break;
        case r'creditRoles':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EditableField)]),
          ) as BuiltList<EditableField>;
          result.creditRoles.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  KindFields deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = KindFieldsBuilder();
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

