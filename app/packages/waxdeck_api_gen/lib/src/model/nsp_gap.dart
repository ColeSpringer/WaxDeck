//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'nsp_gap.g.dart';

/// One part of a rule or an NSP document with no faithful counterpart on the other side.  `field` and `op` are written in the vocabulary of the side being *read*, which is what the report's `direction` says: WaxDeck's names on an export, Navidrome's on an import. A gap names what the walk examined before it stopped - a leaf is checked field first, then operator, then value - so a `field` gap carries no `op` because the operator was never reached, while an `operator` gap carries the field it was used on. 
///
/// Properties:
/// * [kind] - Why this part has no counterpart. `field` and `operator` are the common two; `value` is a value outside the other side's domain (a rating that is not a whole number of stars); `shape` is a rule shape such as a negation that is not `notContains`; `sort`, `limit` and `entity` are the document's other clauses; `malformed` is import-only and means the document is broken rather than unmappable. 
/// * [field] - The field this gap is about, where one is named.
/// * [op] - The operator this gap is about, where one is named.
/// * [value] - The offending value on a `value` gap, so a client can render it without picking `reason` apart. Any JSON type, since it is whatever the rule or the document held. 
/// * [path] - An RFC 6901 JSON Pointer to the offending part, so an editor can point at it rather than describe it. On an export it dereferences against the playlist's `SmartRule` (`/root/...`, `/sorts/0`, `/limitMode`); on an import, against the document that was sent. The empty pointer is RFC 6901's whole document, which is what an import answers for a fault that has no one place - a document with no `all`/`any` root group, or with two. 
/// * [reason] - The sentence the strict conversion would refuse with for this gap. Written by the converter about what the caller built, so a client renders it as-is rather than mapping it to a phrase of its own. 
@BuiltValue()
abstract class NspGap implements Built<NspGap, NspGapBuilder> {
  /// Why this part has no counterpart. `field` and `operator` are the common two; `value` is a value outside the other side's domain (a rating that is not a whole number of stars); `shape` is a rule shape such as a negation that is not `notContains`; `sort`, `limit` and `entity` are the document's other clauses; `malformed` is import-only and means the document is broken rather than unmappable. 
  @BuiltValueField(wireName: r'kind')
  NspGapKindEnum get kind;
  // enum kindEnum {  field,  operator,  value,  shape,  sort,  limit,  entity,  malformed,  };

  /// The field this gap is about, where one is named.
  @BuiltValueField(wireName: r'field')
  String? get field;

  /// The operator this gap is about, where one is named.
  @BuiltValueField(wireName: r'op')
  String? get op;

  /// The offending value on a `value` gap, so a client can render it without picking `reason` apart. Any JSON type, since it is whatever the rule or the document held. 
  @BuiltValueField(wireName: r'value')
  JsonObject? get value;

  /// An RFC 6901 JSON Pointer to the offending part, so an editor can point at it rather than describe it. On an export it dereferences against the playlist's `SmartRule` (`/root/...`, `/sorts/0`, `/limitMode`); on an import, against the document that was sent. The empty pointer is RFC 6901's whole document, which is what an import answers for a fault that has no one place - a document with no `all`/`any` root group, or with two. 
  @BuiltValueField(wireName: r'path')
  String get path;

  /// The sentence the strict conversion would refuse with for this gap. Written by the converter about what the caller built, so a client renders it as-is rather than mapping it to a phrase of its own. 
  @BuiltValueField(wireName: r'reason')
  String get reason;

  NspGap._();

  factory NspGap([void updates(NspGapBuilder b)]) = _$NspGap;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NspGapBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NspGap> get serializer => _$NspGapSerializer();
}

class _$NspGapSerializer implements PrimitiveSerializer<NspGap> {
  @override
  final Iterable<Type> types = const [NspGap, _$NspGap];

  @override
  final String wireName = r'NspGap';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NspGap object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(NspGapKindEnum),
    );
    if (object.field != null) {
      yield r'field';
      yield serializers.serialize(
        object.field,
        specifiedType: const FullType(String),
      );
    }
    if (object.op != null) {
      yield r'op';
      yield serializers.serialize(
        object.op,
        specifiedType: const FullType(String),
      );
    }
    if (object.value != null) {
      yield r'value';
      yield serializers.serialize(
        object.value,
        specifiedType: const FullType.nullable(JsonObject),
      );
    }
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    NspGap object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NspGapBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(NspGapKindEnum),
          ) as NspGapKindEnum;
          result.kind = valueDes;
          break;
        case r'field':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.field = valueDes;
          break;
        case r'op':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.op = valueDes;
          break;
        case r'value':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(JsonObject),
          ) as JsonObject?;
          if (valueDes == null) continue;
          result.value = valueDes;
          break;
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.path = valueDes;
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NspGap deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NspGapBuilder();
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

class NspGapKindEnum extends EnumClass {

  /// Why this part has no counterpart. `field` and `operator` are the common two; `value` is a value outside the other side's domain (a rating that is not a whole number of stars); `shape` is a rule shape such as a negation that is not `notContains`; `sort`, `limit` and `entity` are the document's other clauses; `malformed` is import-only and means the document is broken rather than unmappable. 
  @BuiltValueEnumConst(wireName: r'field')
  static const NspGapKindEnum field = _$nspGapKindEnum_field;
  /// Why this part has no counterpart. `field` and `operator` are the common two; `value` is a value outside the other side's domain (a rating that is not a whole number of stars); `shape` is a rule shape such as a negation that is not `notContains`; `sort`, `limit` and `entity` are the document's other clauses; `malformed` is import-only and means the document is broken rather than unmappable. 
  @BuiltValueEnumConst(wireName: r'operator')
  static const NspGapKindEnum operator_ = _$nspGapKindEnum_operator_;
  /// Why this part has no counterpart. `field` and `operator` are the common two; `value` is a value outside the other side's domain (a rating that is not a whole number of stars); `shape` is a rule shape such as a negation that is not `notContains`; `sort`, `limit` and `entity` are the document's other clauses; `malformed` is import-only and means the document is broken rather than unmappable. 
  @BuiltValueEnumConst(wireName: r'value')
  static const NspGapKindEnum value = _$nspGapKindEnum_value;
  /// Why this part has no counterpart. `field` and `operator` are the common two; `value` is a value outside the other side's domain (a rating that is not a whole number of stars); `shape` is a rule shape such as a negation that is not `notContains`; `sort`, `limit` and `entity` are the document's other clauses; `malformed` is import-only and means the document is broken rather than unmappable. 
  @BuiltValueEnumConst(wireName: r'shape')
  static const NspGapKindEnum shape = _$nspGapKindEnum_shape;
  /// Why this part has no counterpart. `field` and `operator` are the common two; `value` is a value outside the other side's domain (a rating that is not a whole number of stars); `shape` is a rule shape such as a negation that is not `notContains`; `sort`, `limit` and `entity` are the document's other clauses; `malformed` is import-only and means the document is broken rather than unmappable. 
  @BuiltValueEnumConst(wireName: r'sort')
  static const NspGapKindEnum sort = _$nspGapKindEnum_sort;
  /// Why this part has no counterpart. `field` and `operator` are the common two; `value` is a value outside the other side's domain (a rating that is not a whole number of stars); `shape` is a rule shape such as a negation that is not `notContains`; `sort`, `limit` and `entity` are the document's other clauses; `malformed` is import-only and means the document is broken rather than unmappable. 
  @BuiltValueEnumConst(wireName: r'limit')
  static const NspGapKindEnum limit = _$nspGapKindEnum_limit;
  /// Why this part has no counterpart. `field` and `operator` are the common two; `value` is a value outside the other side's domain (a rating that is not a whole number of stars); `shape` is a rule shape such as a negation that is not `notContains`; `sort`, `limit` and `entity` are the document's other clauses; `malformed` is import-only and means the document is broken rather than unmappable. 
  @BuiltValueEnumConst(wireName: r'entity')
  static const NspGapKindEnum entity = _$nspGapKindEnum_entity;
  /// Why this part has no counterpart. `field` and `operator` are the common two; `value` is a value outside the other side's domain (a rating that is not a whole number of stars); `shape` is a rule shape such as a negation that is not `notContains`; `sort`, `limit` and `entity` are the document's other clauses; `malformed` is import-only and means the document is broken rather than unmappable. 
  @BuiltValueEnumConst(wireName: r'malformed')
  static const NspGapKindEnum malformed = _$nspGapKindEnum_malformed;
  /// Why this part has no counterpart. `field` and `operator` are the common two; `value` is a value outside the other side's domain (a rating that is not a whole number of stars); `shape` is a rule shape such as a negation that is not `notContains`; `sort`, `limit` and `entity` are the document's other clauses; `malformed` is import-only and means the document is broken rather than unmappable. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const NspGapKindEnum unknownDefaultOpenApi = _$nspGapKindEnum_unknownDefaultOpenApi;

  static Serializer<NspGapKindEnum> get serializer => _$nspGapKindEnumSerializer;

  const NspGapKindEnum._(String name): super(name);

  static BuiltSet<NspGapKindEnum> get values => _$nspGapKindEnumValues;
  static NspGapKindEnum valueOf(String name) => _$nspGapKindEnumValueOf(name);
}

