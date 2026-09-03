//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item_acquisition.g.dart';

/// How and where the item entered the library: recorded evidence first, and a field only where somebody has corrected it. It is derived from what the import saw - an acquisition the server performed, or the file's own `SOURCE_URL`/`SOURCE_ID` tags - and `PUT`/`DELETE /items/{pid}/acquisition` are what put a wrong one right, under the same curate gate as the rest of the editor.  Present whenever the catalog holds an origin row, which includes a scanned file carrying acquisition tags; absent means no evidence of origin was ever seen. Absence is the ordinary state of a locally ripped file and is not an error. 
///
/// Properties:
/// * [sourceType] - How the item arrived: `manual` (acquired by means the catalog did not record - which is what a tag-derived row reads, and what an import that named no provider stamps), `rss`, or `youtube`. Those three are what the catalog stores, and the write surface refuses anything else - but treat an unknown value as opaque and show it as it stands rather than as an error, since a value can arrive from a catalog another host wrote. `manual` is much the commonest and says only that origin evidence exists, so read `sourceUrl` for the substance.  `local` is defined upstream for an item with no remote origin, and this server never writes it: such an item has no acquisition row at all, and so no block here. A client should still handle it, because the value can arrive from a catalog another host wrote. 
/// * [sourceUrl] - Where it came from, redacted for sharing: emitted only for `http`/`https` origins, and reduced to scheme, host and path - userinfo, query and fragment are dropped. The read answers every user who can see the item while the stored value is verbatim (a credentialed feed URL, a signed download link, a local path), so what is not safe for all of them is not emitted at all. Absent means the stored origin was not an http URL, or was empty; it never means the origin is unknown.  The path is kept, because without it the field says only which host and answers nothing. A secret carried in a path segment rather than the query therefore survives the redaction - the trade is deliberate, and the exposure is to accounts that can already see and stream the item. 
/// * [sourceId] - The origin's own identifier in the provider's namespace - a feed's guid, a video id. Emitted verbatim rather than redacted like `sourceUrl`: an id is not a URL and carries no credentials, and it is the field a correction most often needs to see before rewriting. 
/// * [provider] - The acquisition provider that answered, when one did.
/// * [acquiredAt] - When the item was acquired, as the catalog recorded it. Optional rather than required because a row whose time the catalog does not hold is better described by its absence than by a timestamp at the start of the era, which a client would render as a confident wrong date. 
/// * [locked] - Whether the origin is locked against automatic rewrites - an import re-recording over it, or a scan re-deriving it from tags still in the file. Set by a correction through `PUT`/`DELETE /items/{pid}/acquisition` by default, and by nothing else; `acquisition` on `/items/{pid}/locks` is the same lock under its field name. 
@BuiltValue()
abstract class ItemAcquisition implements Built<ItemAcquisition, ItemAcquisitionBuilder> {
  /// How the item arrived: `manual` (acquired by means the catalog did not record - which is what a tag-derived row reads, and what an import that named no provider stamps), `rss`, or `youtube`. Those three are what the catalog stores, and the write surface refuses anything else - but treat an unknown value as opaque and show it as it stands rather than as an error, since a value can arrive from a catalog another host wrote. `manual` is much the commonest and says only that origin evidence exists, so read `sourceUrl` for the substance.  `local` is defined upstream for an item with no remote origin, and this server never writes it: such an item has no acquisition row at all, and so no block here. A client should still handle it, because the value can arrive from a catalog another host wrote. 
  @BuiltValueField(wireName: r'sourceType')
  String get sourceType;

  /// Where it came from, redacted for sharing: emitted only for `http`/`https` origins, and reduced to scheme, host and path - userinfo, query and fragment are dropped. The read answers every user who can see the item while the stored value is verbatim (a credentialed feed URL, a signed download link, a local path), so what is not safe for all of them is not emitted at all. Absent means the stored origin was not an http URL, or was empty; it never means the origin is unknown.  The path is kept, because without it the field says only which host and answers nothing. A secret carried in a path segment rather than the query therefore survives the redaction - the trade is deliberate, and the exposure is to accounts that can already see and stream the item. 
  @BuiltValueField(wireName: r'sourceUrl')
  String? get sourceUrl;

  /// The origin's own identifier in the provider's namespace - a feed's guid, a video id. Emitted verbatim rather than redacted like `sourceUrl`: an id is not a URL and carries no credentials, and it is the field a correction most often needs to see before rewriting. 
  @BuiltValueField(wireName: r'sourceId')
  String? get sourceId;

  /// The acquisition provider that answered, when one did.
  @BuiltValueField(wireName: r'provider')
  String? get provider;

  /// When the item was acquired, as the catalog recorded it. Optional rather than required because a row whose time the catalog does not hold is better described by its absence than by a timestamp at the start of the era, which a client would render as a confident wrong date. 
  @BuiltValueField(wireName: r'acquiredAt')
  DateTime? get acquiredAt;

  /// Whether the origin is locked against automatic rewrites - an import re-recording over it, or a scan re-deriving it from tags still in the file. Set by a correction through `PUT`/`DELETE /items/{pid}/acquisition` by default, and by nothing else; `acquisition` on `/items/{pid}/locks` is the same lock under its field name. 
  @BuiltValueField(wireName: r'locked')
  bool? get locked;

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
    if (object.locked != null) {
      yield r'locked';
      yield serializers.serialize(
        object.locked,
        specifiedType: const FullType(bool),
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
        case r'locked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.locked = valueDes;
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

