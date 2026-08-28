//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item_acquisition.g.dart';

/// How and where the item entered the library: recorded evidence, not a field. It is derived from what the import saw - an acquisition the server performed, or the file's own `SOURCE_URL`/`SOURCE_ID` tags - and no endpoint edits it, so a client draws it as a read-only caption rather than a form line.  Present whenever the catalog holds an origin row, which includes a scanned file carrying acquisition tags; absent means no evidence of origin was ever seen. Absence is the ordinary state of a locally ripped file and is not an error. 
///
/// Properties:
/// * [sourceType] - How the item arrived: `manual` (acquired by means the catalog did not record - which is what a tag-derived row reads, and what an import that named no provider stamps), `rss`, `youtube`, or whatever an acquisition provider stamped. Open set; treat an unknown value as opaque and show it as it stands. `manual` is much the commonest value and says only that origin evidence exists, so read `sourceUrl` for the substance.  `local` is defined upstream for an item with no remote origin, and this server never writes it: such an item has no acquisition row at all, and so no block here. A client should still handle it, because the value can arrive from a catalog another host wrote. 
/// * [sourceUrl] - Where it came from, redacted for sharing: emitted only for `http`/`https` origins, and reduced to scheme, host and path - userinfo, query and fragment are dropped. The read answers every user who can see the item while the stored value is verbatim (a credentialed feed URL, a signed download link, a local path), so what is not safe for all of them is not emitted at all. Absent means the stored origin was not an http URL, or was empty; it never means the origin is unknown.  The path is kept, because without it the field says only which host and answers nothing. A secret carried in a path segment rather than the query therefore survives the redaction - the trade is deliberate, and the exposure is to accounts that can already see and stream the item. 
/// * [provider] - The acquisition provider that answered, when one did.
/// * [acquiredAt] - When the item was acquired, as the catalog recorded it. Optional rather than required because a row whose time the catalog does not hold is better described by its absence than by a timestamp at the start of the era, which a client would render as a confident wrong date. 
@BuiltValue()
abstract class ItemAcquisition implements Built<ItemAcquisition, ItemAcquisitionBuilder> {
  /// How the item arrived: `manual` (acquired by means the catalog did not record - which is what a tag-derived row reads, and what an import that named no provider stamps), `rss`, `youtube`, or whatever an acquisition provider stamped. Open set; treat an unknown value as opaque and show it as it stands. `manual` is much the commonest value and says only that origin evidence exists, so read `sourceUrl` for the substance.  `local` is defined upstream for an item with no remote origin, and this server never writes it: such an item has no acquisition row at all, and so no block here. A client should still handle it, because the value can arrive from a catalog another host wrote. 
  @BuiltValueField(wireName: r'sourceType')
  String get sourceType;

  /// Where it came from, redacted for sharing: emitted only for `http`/`https` origins, and reduced to scheme, host and path - userinfo, query and fragment are dropped. The read answers every user who can see the item while the stored value is verbatim (a credentialed feed URL, a signed download link, a local path), so what is not safe for all of them is not emitted at all. Absent means the stored origin was not an http URL, or was empty; it never means the origin is unknown.  The path is kept, because without it the field says only which host and answers nothing. A secret carried in a path segment rather than the query therefore survives the redaction - the trade is deliberate, and the exposure is to accounts that can already see and stream the item. 
  @BuiltValueField(wireName: r'sourceUrl')
  String? get sourceUrl;

  /// The acquisition provider that answered, when one did.
  @BuiltValueField(wireName: r'provider')
  String? get provider;

  /// When the item was acquired, as the catalog recorded it. Optional rather than required because a row whose time the catalog does not hold is better described by its absence than by a timestamp at the start of the era, which a client would render as a confident wrong date. 
  @BuiltValueField(wireName: r'acquiredAt')
  DateTime? get acquiredAt;

  ItemAcquisition._();

  factory ItemAcquisition([void updates(ItemAcquisitionBuilder b)]) = _$ItemAcquisition;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ItemAcquisitionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ItemAcquisition> get serializer => _$ItemAcquisitionSerializer();
}

class _$ItemAcquisitionSerializer implements PrimitiveSerializer<ItemAcquisition> {
  @override
  final Iterable<Type> types = const [ItemAcquisition, _$ItemAcquisition];

  @override
  final String wireName = r'ItemAcquisition';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ItemAcquisition object, {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    ItemAcquisition object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ItemAcquisitionBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ItemAcquisition deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ItemAcquisitionBuilder();
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

