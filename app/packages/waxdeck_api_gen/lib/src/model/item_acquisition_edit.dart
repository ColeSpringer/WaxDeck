//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item_acquisition_edit.g.dart';

/// A replacement origin row. The four columns below are written as sent - an absent one is **cleared**, since the whole point of this surface is lowering a value the merge-wise recorder cannot. Two the body cannot express (the provider's version string and the acquisition's stored options) carry forward from the standing row. 
///
/// Properties:
/// * [sourceType] - How the item arrived. The set is closed - `manual`, `rss`, `youtube` - and anything else is refused with `invalid-request` rather than stored. `local` is refused too, for a different reason: it means \"no remote origin\", which is spelled by having no row at all, so clear the origin instead of asking for it. 
/// * [sourceUrl] - Where it came from, stored verbatim. **Absent keeps the standing value; `\"\"` clears it.** The one column that works that way, because it is the one the read redacts: a client is never shown the stored string in full, so treating a resent value as authoritative would let a round trip through this form destroy a query string or a path segment nobody saw. A corrected URL cannot be confirmed by reading it back either, for the same reason. 
/// * [sourceId] - The origin's identifier in the provider's namespace.
/// * [provider] - The acquisition provider that supplied the item.
/// * [acquiredAt] - When it was acquired. Absent keeps the stamp the row already carries rather than restamping it, so correcting a URL does not rewrite the date as well. 
/// * [writeBack] - Mirror the origin into the files' acquisition tags, which is what makes the correction survive a rescan. 
/// * [lock] - Lock `acquisition` against automatic rewrites.
/// * [force] - Write through a standing lock.
@BuiltValue()
abstract class ItemAcquisitionEdit implements Built<ItemAcquisitionEdit, ItemAcquisitionEditBuilder> {
  /// How the item arrived. The set is closed - `manual`, `rss`, `youtube` - and anything else is refused with `invalid-request` rather than stored. `local` is refused too, for a different reason: it means \"no remote origin\", which is spelled by having no row at all, so clear the origin instead of asking for it. 
  @BuiltValueField(wireName: r'sourceType')
  String get sourceType;

  /// Where it came from, stored verbatim. **Absent keeps the standing value; `\"\"` clears it.** The one column that works that way, because it is the one the read redacts: a client is never shown the stored string in full, so treating a resent value as authoritative would let a round trip through this form destroy a query string or a path segment nobody saw. A corrected URL cannot be confirmed by reading it back either, for the same reason. 
  @BuiltValueField(wireName: r'sourceUrl')
  String? get sourceUrl;

  /// The origin's identifier in the provider's namespace.
  @BuiltValueField(wireName: r'sourceId')
  String? get sourceId;

  /// The acquisition provider that supplied the item.
  @BuiltValueField(wireName: r'provider')
  String? get provider;

  /// When it was acquired. Absent keeps the stamp the row already carries rather than restamping it, so correcting a URL does not rewrite the date as well. 
  @BuiltValueField(wireName: r'acquiredAt')
  DateTime? get acquiredAt;

  /// Mirror the origin into the files' acquisition tags, which is what makes the correction survive a rescan. 
  @BuiltValueField(wireName: r'writeBack')
  bool? get writeBack;

  /// Lock `acquisition` against automatic rewrites.
  @BuiltValueField(wireName: r'lock')
  bool? get lock;

  /// Write through a standing lock.
  @BuiltValueField(wireName: r'force')
  bool? get force;

  ItemAcquisitionEdit._();

  factory ItemAcquisitionEdit([void updates(ItemAcquisitionEditBuilder b)]) = _$ItemAcquisitionEdit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ItemAcquisitionEditBuilder b) => b
      ..writeBack = false
      ..lock = true
      ..force = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<ItemAcquisitionEdit> get serializer => _$ItemAcquisitionEditSerializer();
}

class _$ItemAcquisitionEditSerializer implements PrimitiveSerializer<ItemAcquisitionEdit> {
  @override
  final Iterable<Type> types = const [ItemAcquisitionEdit, _$ItemAcquisitionEdit];

  @override
  final String wireName = r'ItemAcquisitionEdit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ItemAcquisitionEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'sourceType';
    yield serializers.serialize(
      object.sourceType,
      specifiedType: const FullType(String),
    );
    if (object.sourceUrl != null) {
      yield r'sourceUrl';
      yield serializers.serialize(
        object.sourceUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.sourceId != null) {
      yield r'sourceId';
      yield serializers.serialize(
        object.sourceId,
        specifiedType: const FullType(String),
      );
    }
    if (object.provider != null) {
      yield r'provider';
      yield serializers.serialize(
        object.provider,
        specifiedType: const FullType(String),
      );
    }
    if (object.acquiredAt != null) {
      yield r'acquiredAt';
      yield serializers.serialize(
        object.acquiredAt,
        specifiedType: const FullType(DateTime),
      );
    }
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
    ItemAcquisitionEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ItemAcquisitionEditBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'sourceType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceType = valueDes;
          break;
        case r'sourceUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceUrl = valueDes;
          break;
        case r'sourceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceId = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.provider = valueDes;
          break;
        case r'acquiredAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.acquiredAt = valueDes;
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
  ItemAcquisitionEdit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ItemAcquisitionEditBuilder();
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

