//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'field_provenance.g.dart';

/// Who set one field's current value.
///
/// Properties:
/// * [field] - The field, possibly namespaced.
/// * [source_] - The producer: `tag`, `user`, `enrichment`, or `organize`. A string, not a closed enum. 
/// * [provider] - The enrichment provider, for enriched fields.
/// * [locked] - Whether the field is locked.
/// * [updatedAt] - When the value last changed.
@BuiltValue()
abstract class FieldProvenance implements Built<FieldProvenance, FieldProvenanceBuilder> {
  /// The field, possibly namespaced.
  @BuiltValueField(wireName: r'field')
  String get field;

  /// The producer: `tag`, `user`, `enrichment`, or `organize`. A string, not a closed enum. 
  @BuiltValueField(wireName: r'source')
  String get source_;

  /// The enrichment provider, for enriched fields.
  @BuiltValueField(wireName: r'provider')
  String? get provider;

  /// Whether the field is locked.
  @BuiltValueField(wireName: r'locked')
  bool get locked;

  /// When the value last changed.
  @BuiltValueField(wireName: r'updatedAt')
  DateTime? get updatedAt;

  FieldProvenance._();

  factory FieldProvenance([void updates(FieldProvenanceBuilder b)]) = _$FieldProvenance;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FieldProvenanceBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FieldProvenance> get serializer => _$FieldProvenanceSerializer();
}

class _$FieldProvenanceSerializer implements PrimitiveSerializer<FieldProvenance> {
  @override
  final Iterable<Type> types = const [FieldProvenance, _$FieldProvenance];

  @override
  final String wireName = r'FieldProvenance';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FieldProvenance object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'field';
    yield serializers.serialize(
      object.field,
      specifiedType: const FullType(String),
    );
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(String),
    );
    if (object.provider != null) {
      yield r'provider';
      yield serializers.serialize(
        object.provider,
        specifiedType: const FullType(String),
      );
    }
    yield r'locked';
    yield serializers.serialize(
      object.locked,
      specifiedType: const FullType(bool),
    );
    if (object.updatedAt != null) {
      yield r'updatedAt';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    FieldProvenance object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required FieldProvenanceBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'field':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.field = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.source_ = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.provider = valueDes;
          break;
        case r'locked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.locked = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FieldProvenance deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FieldProvenanceBuilder();
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

