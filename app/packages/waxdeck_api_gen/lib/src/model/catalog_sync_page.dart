//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/catalog_sync_entry.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'catalog_sync_page.g.dart';

/// One page of catalog sync entries (snapshot or delta).
///
/// Properties:
/// * [entries] - Mirror entries, coalesced within the page.
/// * [nextCursor] - Keyset cursor for the next snapshot page. Absent on the last snapshot page and on delta pages. 
/// * [nextSince] - Opaque change cursor to sync from next. On snapshot pages it repeats the cursor captured at the snapshot's start; on delta pages it advances past this page's changes. 
/// * [more] - True when another delta page is already available; fetch it immediately with `since` set to this page's `nextSince`. Absent in snapshot mode (`nextCursor` plays that role). 
@BuiltValue()
abstract class CatalogSyncPage implements Built<CatalogSyncPage, CatalogSyncPageBuilder> {
  /// Mirror entries, coalesced within the page.
  @BuiltValueField(wireName: r'entries')
  BuiltList<CatalogSyncEntry> get entries;

  /// Keyset cursor for the next snapshot page. Absent on the last snapshot page and on delta pages. 
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  /// Opaque change cursor to sync from next. On snapshot pages it repeats the cursor captured at the snapshot's start; on delta pages it advances past this page's changes. 
  @BuiltValueField(wireName: r'nextSince')
  String get nextSince;

  /// True when another delta page is already available; fetch it immediately with `since` set to this page's `nextSince`. Absent in snapshot mode (`nextCursor` plays that role). 
  @BuiltValueField(wireName: r'more')
  bool? get more;

  CatalogSyncPage._();

  factory CatalogSyncPage([void updates(CatalogSyncPageBuilder b)]) = _$CatalogSyncPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CatalogSyncPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CatalogSyncPage> get serializer => _$CatalogSyncPageSerializer();
}

class _$CatalogSyncPageSerializer implements PrimitiveSerializer<CatalogSyncPage> {
  @override
  final Iterable<Type> types = const [CatalogSyncPage, _$CatalogSyncPage];

  @override
  final String wireName = r'CatalogSyncPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CatalogSyncPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(CatalogSyncEntry)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
    yield r'nextSince';
    yield serializers.serialize(
      object.nextSince,
      specifiedType: const FullType(String),
    );
    if (object.more != null) {
      yield r'more';
      yield serializers.serialize(
        object.more,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CatalogSyncPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CatalogSyncPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(CatalogSyncEntry)]),
          ) as BuiltList<CatalogSyncEntry>;
          result.entries.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextCursor = valueDes;
          break;
        case r'nextSince':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextSince = valueDes;
          break;
        case r'more':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.more = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CatalogSyncPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CatalogSyncPageBuilder();
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

