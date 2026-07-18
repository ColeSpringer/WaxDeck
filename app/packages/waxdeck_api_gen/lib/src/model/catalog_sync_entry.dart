//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'catalog_sync_entry.g.dart';

/// One mirrored catalog change: an `upsert` carrying the item's current summary, or a `delete` tombstone carrying only the PID. Snapshot pages contain only upserts. `op` is a string, not a closed enum, so new operations can appear; clients must drop entries whose `op` they do not recognize. 
///
/// Properties:
/// * [op] - What the mirror should do with this entry: `upsert` (store `item`) or `delete` (remove the PID). 
/// * [pid] - The item the entry is about.
/// * [item] 
@BuiltValue()
abstract class CatalogSyncEntry implements Built<CatalogSyncEntry, CatalogSyncEntryBuilder> {
  /// What the mirror should do with this entry: `upsert` (store `item`) or `delete` (remove the PID). 
  @BuiltValueField(wireName: r'op')
  String get op;

  /// The item the entry is about.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  @BuiltValueField(wireName: r'item')
  ItemSummary? get item;

  CatalogSyncEntry._();

  factory CatalogSyncEntry([void updates(CatalogSyncEntryBuilder b)]) = _$CatalogSyncEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CatalogSyncEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CatalogSyncEntry> get serializer => _$CatalogSyncEntrySerializer();
}

class _$CatalogSyncEntrySerializer implements PrimitiveSerializer<CatalogSyncEntry> {
  @override
  final Iterable<Type> types = const [CatalogSyncEntry, _$CatalogSyncEntry];

  @override
  final String wireName = r'CatalogSyncEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CatalogSyncEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'op';
    yield serializers.serialize(
      object.op,
      specifiedType: const FullType(String),
    );
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    if (object.item != null) {
      yield r'item';
      yield serializers.serialize(
        object.item,
        specifiedType: const FullType(ItemSummary),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CatalogSyncEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CatalogSyncEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'op':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.op = valueDes;
          break;
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'item':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ItemSummary),
          ) as ItemSummary;
          result.item = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CatalogSyncEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CatalogSyncEntryBuilder();
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

