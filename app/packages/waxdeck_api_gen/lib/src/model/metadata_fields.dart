//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/entity_type_fields.dart';
import 'package:waxdeck_api_gen/src/model/kind_fields.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'metadata_fields.g.dart';

/// The editor's field vocabulary.
///
/// Properties:
/// * [kinds] - Editable fields per item kind.
/// * [entityTypes] - Editable fields per entity type.
/// * [reservedTagKeys] - Custom-tag keys the catalog owns through a field of its own (`BPM` through `bpm`, `ISRC` through `isrc`, and so on), in sorted order. A custom-tag editor refuses one of these before the round trip; `setItemTag` refuses it either way. 
@BuiltValue()
abstract class MetadataFields implements Built<MetadataFields, MetadataFieldsBuilder> {
  /// Editable fields per item kind.
  @BuiltValueField(wireName: r'kinds')
  BuiltList<KindFields> get kinds;

  /// Editable fields per entity type.
  @BuiltValueField(wireName: r'entityTypes')
  BuiltList<EntityTypeFields> get entityTypes;

  /// Custom-tag keys the catalog owns through a field of its own (`BPM` through `bpm`, `ISRC` through `isrc`, and so on), in sorted order. A custom-tag editor refuses one of these before the round trip; `setItemTag` refuses it either way. 
  @BuiltValueField(wireName: r'reservedTagKeys')
  BuiltList<String>? get reservedTagKeys;

  MetadataFields._();

  factory MetadataFields([void updates(MetadataFieldsBuilder b)]) = _$MetadataFields;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MetadataFieldsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MetadataFields> get serializer => _$MetadataFieldsSerializer();
}

class _$MetadataFieldsSerializer implements PrimitiveSerializer<MetadataFields> {
  @override
  final Iterable<Type> types = const [MetadataFields, _$MetadataFields];

  @override
  final String wireName = r'MetadataFields';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MetadataFields object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kinds';
    yield serializers.serialize(
      object.kinds,
      specifiedType: const FullType(BuiltList, [FullType(KindFields)]),
    );
    yield r'entityTypes';
    yield serializers.serialize(
      object.entityTypes,
      specifiedType: const FullType(BuiltList, [FullType(EntityTypeFields)]),
    );
    if (object.reservedTagKeys != null) {
      yield r'reservedTagKeys';
      yield serializers.serialize(
        object.reservedTagKeys,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MetadataFields object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MetadataFieldsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kinds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(KindFields)]),
          ) as BuiltList<KindFields>;
          result.kinds.replace(valueDes);
          break;
        case r'entityTypes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EntityTypeFields)]),
          ) as BuiltList<EntityTypeFields>;
          result.entityTypes.replace(valueDes);
          break;
        case r'reservedTagKeys':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.reservedTagKeys.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MetadataFields deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MetadataFieldsBuilder();
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

