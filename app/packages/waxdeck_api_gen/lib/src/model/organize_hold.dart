//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_hold.g.dart';

/// One move held back, and why.
///
/// Properties:
/// * [itemPid] - The item whose file is held. Absent from an undo's holds, which name files by path. 
/// * [from] - Where the file is: relative to its library when the pass planned one library, otherwise the server's absolute path. 
/// * [to] - Where the move would put it, in the same form; absent when the pass has no place for it. 
/// * [code] - Why it is held: the plan's codes (see `heldByCode`), and for an undo `moved-since` (the file moved again after the run) and `uncataloged` (the catalog no longer holds it). 
/// * [reason] - Why, in words: the catalog's own, or `read-only server` for a move the server's read-only mode holds. 
@BuiltValue()
abstract class OrganizeHold implements Built<OrganizeHold, OrganizeHoldBuilder> {
  /// The item whose file is held. Absent from an undo's holds, which name files by path. 
  @BuiltValueField(wireName: r'itemPid')
  String? get itemPid;

  /// Where the file is: relative to its library when the pass planned one library, otherwise the server's absolute path. 
  @BuiltValueField(wireName: r'from')
  String get from;

  /// Where the move would put it, in the same form; absent when the pass has no place for it. 
  @BuiltValueField(wireName: r'to')
  String? get to;

  /// Why it is held: the plan's codes (see `heldByCode`), and for an undo `moved-since` (the file moved again after the run) and `uncataloged` (the catalog no longer holds it). 
  @BuiltValueField(wireName: r'code')
  OrganizeHoldCodeEnum get code;
  // enum codeEnum {  collision,  occupied,  occupied-case,  untagged,  missing,  virtual,  book-held,  read-only,  moved-since,  uncataloged,  };

  /// Why, in words: the catalog's own, or `read-only server` for a move the server's read-only mode holds. 
  @BuiltValueField(wireName: r'reason')
  String get reason;

  OrganizeHold._();

  factory OrganizeHold([void updates(OrganizeHoldBuilder b)]) = _$OrganizeHold;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeHoldBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeHold> get serializer => _$OrganizeHoldSerializer();
}

class _$OrganizeHoldSerializer implements PrimitiveSerializer<OrganizeHold> {
  @override
  final Iterable<Type> types = const [OrganizeHold, _$OrganizeHold];

  @override
  final String wireName = r'OrganizeHold';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeHold object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.itemPid != null) {
      yield r'itemPid';
      yield serializers.serialize(
        object.itemPid,
        specifiedType: const FullType(String),
      );
    }
    yield r'from';
    yield serializers.serialize(
      object.from,
      specifiedType: const FullType(String),
    );
    if (object.to != null) {
      yield r'to';
      yield serializers.serialize(
        object.to,
        specifiedType: const FullType(String),
      );
    }
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(OrganizeHoldCodeEnum),
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
    OrganizeHold object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeHoldBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'itemPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.itemPid = valueDes;
          break;
        case r'from':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.from = valueDes;
          break;
        case r'to':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.to = valueDes;
          break;
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(OrganizeHoldCodeEnum),
          ) as OrganizeHoldCodeEnum;
          result.code = valueDes;
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
  OrganizeHold deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeHoldBuilder();
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


/// Why it is held: the plan's codes (see `heldByCode`), and for an undo `moved-since` (the file moved again after the run) and `uncataloged` (the catalog no longer holds it). 
class OrganizeHoldCodeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'collision')
  static const OrganizeHoldCodeEnum collision = _$organizeHoldCodeEnum_collision;
  @BuiltValueEnumConst(wireName: r'occupied')
  static const OrganizeHoldCodeEnum occupied = _$organizeHoldCodeEnum_occupied;
  @BuiltValueEnumConst(wireName: r'occupied-case')
  static const OrganizeHoldCodeEnum occupiedCase = _$organizeHoldCodeEnum_occupiedCase;
  @BuiltValueEnumConst(wireName: r'untagged')
  static const OrganizeHoldCodeEnum untagged = _$organizeHoldCodeEnum_untagged;
  @BuiltValueEnumConst(wireName: r'missing')
  static const OrganizeHoldCodeEnum missing = _$organizeHoldCodeEnum_missing;
  @BuiltValueEnumConst(wireName: r'virtual')
  static const OrganizeHoldCodeEnum virtual = _$organizeHoldCodeEnum_virtual;
  @BuiltValueEnumConst(wireName: r'book-held')
  static const OrganizeHoldCodeEnum bookHeld = _$organizeHoldCodeEnum_bookHeld;
  @BuiltValueEnumConst(wireName: r'read-only')
  static const OrganizeHoldCodeEnum readOnly = _$organizeHoldCodeEnum_readOnly;
  @BuiltValueEnumConst(wireName: r'moved-since')
  static const OrganizeHoldCodeEnum movedSince = _$organizeHoldCodeEnum_movedSince;
  @BuiltValueEnumConst(wireName: r'uncataloged')
  static const OrganizeHoldCodeEnum uncataloged = _$organizeHoldCodeEnum_uncataloged;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const OrganizeHoldCodeEnum unknownDefaultOpenApi = _$organizeHoldCodeEnum_unknownDefaultOpenApi;

  static Serializer<OrganizeHoldCodeEnum> get serializer => _$organizeHoldCodeEnumSerializer;

  const OrganizeHoldCodeEnum._(String name): super(name);

  static BuiltSet<OrganizeHoldCodeEnum> get values => _$organizeHoldCodeEnumValues;
  static OrganizeHoldCodeEnum valueOf(String name) => _$organizeHoldCodeEnumValueOf(name);
}

