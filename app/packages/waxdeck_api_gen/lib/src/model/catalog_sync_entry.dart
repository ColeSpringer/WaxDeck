//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/podcast_show.dart';
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:waxdeck_api_gen/src/model/episode_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'catalog_sync_entry.g.dart';

/// One mirrored catalog change: an `upsert` carrying the item's current summary, an `upsert-show` carrying a podcast show's current summary (shows are catalog entities but not items, so they ride their own operation and clients from before this operation existed drop them harmlessly), or a `delete` tombstone carrying the PID and a `reason` (which removes the PID from whichever mirror table holds it). An `upsert` for a podcast episode carries `item` and additionally `episode`, the full episode summary; clients that only know items keep reading `item`. Snapshot pages contain only upserts, of both kinds. `op` is a string, not a closed enum, so new operations can appear; clients must drop entries whose `op` they do not recognize. 
///
/// Properties:
/// * [op] - What the mirror should do with this entry: `upsert` (store `item`, and `episode` when present), `upsert-show` (store `show`), or `delete` (remove the PID). 
/// * [pid] - The item or show the entry is about.
/// * [reason] - Why a `delete` arrived, absent on every other operation. `removed` means the server cannot put it back: the audio was deleted outright rather than to the trash, or the catalog dropped the row. `hidden` means it left this caller's view and is recoverable: deleted to the trash with its undo journal, or a file re-homed under a library they are not granted.  Unsubscribing from a show sends no tombstone at all. It bumps the caller's grant epoch, which retires their cursors and forces a clean re-mirror, so the rows go with the old mirror rather than one delete at a time. Both tombstone the mirror row identically. The difference is what a client may reclaim: bytes it already downloaded, and the artwork pinned beside them, are dead weight after `removed`, and worth keeping after `hidden`, where undoing the transition would otherwise cost the whole transfer again. One case answers `hidden` and later becomes unrecoverable: an item trashed and purged afterwards was tombstoned when it was trashed, and emptying the trash is not itself a catalog change, so no second entry follows it. A client keeps those bytes. Open, like `op`, and deliberately not an enum: a closed one generates a Dart `EnumClass` whose serializer throws on an unrecognized wire value, so adding a third reason later would fail the whole page's deserialization and stop sync rather than degrade. A client that does not recognize a value must treat it as `hidden`, which is the conservative half. 
/// * [item] 
/// * [episode] 
/// * [show_] 
@BuiltValue()
abstract class CatalogSyncEntry implements Built<CatalogSyncEntry, CatalogSyncEntryBuilder> {
  /// What the mirror should do with this entry: `upsert` (store `item`, and `episode` when present), `upsert-show` (store `show`), or `delete` (remove the PID). 
  @BuiltValueField(wireName: r'op')
  String get op;

  /// The item or show the entry is about.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Why a `delete` arrived, absent on every other operation. `removed` means the server cannot put it back: the audio was deleted outright rather than to the trash, or the catalog dropped the row. `hidden` means it left this caller's view and is recoverable: deleted to the trash with its undo journal, or a file re-homed under a library they are not granted.  Unsubscribing from a show sends no tombstone at all. It bumps the caller's grant epoch, which retires their cursors and forces a clean re-mirror, so the rows go with the old mirror rather than one delete at a time. Both tombstone the mirror row identically. The difference is what a client may reclaim: bytes it already downloaded, and the artwork pinned beside them, are dead weight after `removed`, and worth keeping after `hidden`, where undoing the transition would otherwise cost the whole transfer again. One case answers `hidden` and later becomes unrecoverable: an item trashed and purged afterwards was tombstoned when it was trashed, and emptying the trash is not itself a catalog change, so no second entry follows it. A client keeps those bytes. Open, like `op`, and deliberately not an enum: a closed one generates a Dart `EnumClass` whose serializer throws on an unrecognized wire value, so adding a third reason later would fail the whole page's deserialization and stop sync rather than degrade. A client that does not recognize a value must treat it as `hidden`, which is the conservative half. 
  @BuiltValueField(wireName: r'reason')
  String? get reason;

  @BuiltValueField(wireName: r'item')
  ItemSummary? get item;

  @BuiltValueField(wireName: r'episode')
  EpisodeSummary? get episode;

  @BuiltValueField(wireName: r'show')
  PodcastShow? get show_;

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
    if (object.reason != null) {
      yield r'reason';
      yield serializers.serialize(
        object.reason,
        specifiedType: const FullType(String),
      );
    }
    if (object.item != null) {
      yield r'item';
      yield serializers.serialize(
        object.item,
        specifiedType: const FullType(ItemSummary),
      );
    }
    if (object.episode != null) {
      yield r'episode';
      yield serializers.serialize(
        object.episode,
        specifiedType: const FullType(EpisodeSummary),
      );
    }
    if (object.show_ != null) {
      yield r'show';
      yield serializers.serialize(
        object.show_,
        specifiedType: const FullType(PodcastShow),
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
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        case r'item':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ItemSummary),
          ) as ItemSummary;
          result.item = valueDes;
          break;
        case r'episode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EpisodeSummary),
          ) as EpisodeSummary;
          result.episode = valueDes;
          break;
        case r'show':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PodcastShow),
          ) as PodcastShow;
          result.show_.replace(valueDes);
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

