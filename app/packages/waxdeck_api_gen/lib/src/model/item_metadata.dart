//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/item_acquisition.dart';
import 'package:waxdeck_api_gen/src/model/lyrics_state.dart';
import 'package:waxdeck_api_gen/src/model/write_back_issue.dart';
import 'package:waxdeck_api_gen/src/model/field_provenance.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/chapter_mark.dart';
import 'package:waxdeck_api_gen/src/model/custom_tag.dart';
import 'package:waxdeck_api_gen/src/model/credit.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item_metadata.g.dart';

/// Everything the editor shows for one item.
///
/// Properties:
/// * [pid] - The item.
/// * [mediaType] 
/// * [fields] - The item's scalar fields by name (the kind's vocabulary from the fields endpoint); empty values are omitted. 
/// * [lockedFields] - Currently locked fields, including namespaced artifacts (`lyrics`, `art`, `credit.ROLE`, `tag.KEY`). 
/// * [provenance] - Per-field provenance for curated fields.
/// * [credits] - Credits by role.
/// * [lyrics] 
/// * [chapters] - Chapter marks (books).
/// * [customTags] - Custom tags.
/// * [unofficial] - Whether the item is marked as having no canonical release.
/// * [virtualTrack] - True for tracks carved from a shared file (CUE rips): their edits are always database-only and they export no fingerprint, by upstream design. 
/// * [hasArtwork] - Whether the item resolves any front cover, including one inherited from its album, release group, or artist. 
/// * [hasOwnArtwork] - Whether the item holds its own front cover, as opposed to inheriting one from the entity chain. Lets the editor tell an item-level cover from an inherited one. 
/// * [albumPid] - The item's album entity, when any.
/// * [artistPid] - The item's artist entity, when any.
/// * [releaseGroupPid] - The item's release group entity, when any.
/// * [writeBackIssues] - Files whose on-disk tags are out of step with the catalog (failed write-backs, values the format cannot store). 
/// * [mayCurate] - Whether the caller may run the item-scoped edits this document describes: administrators always, everyone else exactly for the items their own uploads brought in. The read answers anyone who can see the item, so without this a client has no way to tell an editor it can save from one every save will be refused. Optional for compatibility; absent reads as unknown, and a client that treats it as false only withholds a door the server would have refused anyway. 
/// * [acquisition] 
@BuiltValue()
abstract class ItemMetadata implements Built<ItemMetadata, ItemMetadataBuilder> {
  /// The item.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  /// The item's scalar fields by name (the kind's vocabulary from the fields endpoint); empty values are omitted. 
  @BuiltValueField(wireName: r'fields')
  BuiltMap<String, String> get fields;

  /// Currently locked fields, including namespaced artifacts (`lyrics`, `art`, `credit.ROLE`, `tag.KEY`). 
  @BuiltValueField(wireName: r'lockedFields')
  BuiltList<String> get lockedFields;

  /// Per-field provenance for curated fields.
  @BuiltValueField(wireName: r'provenance')
  BuiltList<FieldProvenance> get provenance;

  /// Credits by role.
  @BuiltValueField(wireName: r'credits')
  BuiltList<Credit> get credits;

  @BuiltValueField(wireName: r'lyrics')
  LyricsState? get lyrics;

  /// Chapter marks (books).
  @BuiltValueField(wireName: r'chapters')
  BuiltList<ChapterMark>? get chapters;

  /// Custom tags.
  @BuiltValueField(wireName: r'customTags')
  BuiltList<CustomTag> get customTags;

  /// Whether the item is marked as having no canonical release.
  @BuiltValueField(wireName: r'unofficial')
  bool get unofficial;

  /// True for tracks carved from a shared file (CUE rips): their edits are always database-only and they export no fingerprint, by upstream design. 
  @BuiltValueField(wireName: r'virtualTrack')
  bool get virtualTrack;

  /// Whether the item resolves any front cover, including one inherited from its album, release group, or artist. 
  @BuiltValueField(wireName: r'hasArtwork')
  bool get hasArtwork;

  /// Whether the item holds its own front cover, as opposed to inheriting one from the entity chain. Lets the editor tell an item-level cover from an inherited one. 
  @BuiltValueField(wireName: r'hasOwnArtwork')
  bool get hasOwnArtwork;

  /// The item's album entity, when any.
  @BuiltValueField(wireName: r'albumPid')
  String? get albumPid;

  /// The item's artist entity, when any.
  @BuiltValueField(wireName: r'artistPid')
  String? get artistPid;

  /// The item's release group entity, when any.
  @BuiltValueField(wireName: r'releaseGroupPid')
  String? get releaseGroupPid;

  /// Files whose on-disk tags are out of step with the catalog (failed write-backs, values the format cannot store). 
  @BuiltValueField(wireName: r'writeBackIssues')
  BuiltList<WriteBackIssue> get writeBackIssues;

  /// Whether the caller may run the item-scoped edits this document describes: administrators always, everyone else exactly for the items their own uploads brought in. The read answers anyone who can see the item, so without this a client has no way to tell an editor it can save from one every save will be refused. Optional for compatibility; absent reads as unknown, and a client that treats it as false only withholds a door the server would have refused anyway. 
  @BuiltValueField(wireName: r'mayCurate')
  bool? get mayCurate;

  @BuiltValueField(wireName: r'acquisition')
  ItemAcquisition? get acquisition;

  ItemMetadata._();

  factory ItemMetadata([void updates(ItemMetadataBuilder b)]) = _$ItemMetadata;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ItemMetadataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ItemMetadata> get serializer => _$ItemMetadataSerializer();
}

class _$ItemMetadataSerializer implements PrimitiveSerializer<ItemMetadata> {
  @override
  final Iterable<Type> types = const [ItemMetadata, _$ItemMetadata];

  @override
  final String wireName = r'ItemMetadata';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ItemMetadata object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'mediaType';
    yield serializers.serialize(
      object.mediaType,
      specifiedType: const FullType(MediaType),
    );
    yield r'fields';
    yield serializers.serialize(
      object.fields,
      specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
    );
    yield r'lockedFields';
    yield serializers.serialize(
      object.lockedFields,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'provenance';
    yield serializers.serialize(
      object.provenance,
      specifiedType: const FullType(BuiltList, [FullType(FieldProvenance)]),
    );
    yield r'credits';
    yield serializers.serialize(
      object.credits,
      specifiedType: const FullType(BuiltList, [FullType(Credit)]),
    );
    if (object.lyrics != null) {
      yield r'lyrics';
      yield serializers.serialize(
        object.lyrics,
        specifiedType: const FullType(LyricsState),
      );
    }
    if (object.chapters != null) {
      yield r'chapters';
      yield serializers.serialize(
        object.chapters,
        specifiedType: const FullType(BuiltList, [FullType(ChapterMark)]),
      );
    }
    yield r'customTags';
    yield serializers.serialize(
      object.customTags,
      specifiedType: const FullType(BuiltList, [FullType(CustomTag)]),
    );
    yield r'unofficial';
    yield serializers.serialize(
      object.unofficial,
      specifiedType: const FullType(bool),
    );
    yield r'virtualTrack';
    yield serializers.serialize(
      object.virtualTrack,
      specifiedType: const FullType(bool),
    );
    yield r'hasArtwork';
    yield serializers.serialize(
      object.hasArtwork,
      specifiedType: const FullType(bool),
    );
    yield r'hasOwnArtwork';
    yield serializers.serialize(
      object.hasOwnArtwork,
      specifiedType: const FullType(bool),
    );
    if (object.albumPid != null) {
      yield r'albumPid';
      yield serializers.serialize(
        object.albumPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.artistPid != null) {
      yield r'artistPid';
      yield serializers.serialize(
        object.artistPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.releaseGroupPid != null) {
      yield r'releaseGroupPid';
      yield serializers.serialize(
        object.releaseGroupPid,
        specifiedType: const FullType(String),
      );
    }
    yield r'writeBackIssues';
    yield serializers.serialize(
      object.writeBackIssues,
      specifiedType: const FullType(BuiltList, [FullType(WriteBackIssue)]),
    );
    if (object.mayCurate != null) {
      yield r'mayCurate';
      yield serializers.serialize(
        object.mayCurate,
        specifiedType: const FullType(bool),
      );
    }
    if (object.acquisition != null) {
      yield r'acquisition';
      yield serializers.serialize(
        object.acquisition,
        specifiedType: const FullType(ItemAcquisition),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ItemMetadata object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ItemMetadataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'mediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaType),
          ) as MediaType;
          result.mediaType = valueDes;
          break;
        case r'fields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
          ) as BuiltMap<String, String>;
          result.fields.replace(valueDes);
          break;
        case r'lockedFields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.lockedFields.replace(valueDes);
          break;
        case r'provenance':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(FieldProvenance)]),
          ) as BuiltList<FieldProvenance>;
          result.provenance.replace(valueDes);
          break;
        case r'credits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Credit)]),
          ) as BuiltList<Credit>;
          result.credits.replace(valueDes);
          break;
        case r'lyrics':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LyricsState),
          ) as LyricsState;
          result.lyrics.replace(valueDes);
          break;
        case r'chapters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ChapterMark)]),
          ) as BuiltList<ChapterMark>;
          result.chapters.replace(valueDes);
          break;
        case r'customTags':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(CustomTag)]),
          ) as BuiltList<CustomTag>;
          result.customTags.replace(valueDes);
          break;
        case r'unofficial':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.unofficial = valueDes;
          break;
        case r'virtualTrack':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.virtualTrack = valueDes;
          break;
        case r'hasArtwork':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasArtwork = valueDes;
          break;
        case r'hasOwnArtwork':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasOwnArtwork = valueDes;
          break;
        case r'albumPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.albumPid = valueDes;
          break;
        case r'artistPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artistPid = valueDes;
          break;
        case r'releaseGroupPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.releaseGroupPid = valueDes;
          break;
        case r'writeBackIssues':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(WriteBackIssue)]),
          ) as BuiltList<WriteBackIssue>;
          result.writeBackIssues.replace(valueDes);
          break;
        case r'mayCurate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.mayCurate = valueDes;
          break;
        case r'acquisition':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ItemAcquisition),
          ) as ItemAcquisition;
          result.acquisition.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ItemMetadata deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ItemMetadataBuilder();
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

