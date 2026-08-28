//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/commit_credits.dart';
import 'package:waxdeck_api_gen/src/model/commit_lyrics.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/chapter_mark.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'metadata_commit.g.dart';

/// The staged parts of one item's editor draft. Every part is optional and at least one is required; an empty body answers `invalid-request` rather than committing nothing successfully.  The three write switches are hoisted out of the per-part bodies the sequential endpoints take, because a draft is saved with one set of them. 
///
/// Properties:
/// * [fields] - Field name to new value; an empty string clears the field. Names come from the kind's vocabulary, as for `editItemMetadata`. 
/// * [credits] - Replacement people per role, applied in the order given. 
/// * [lyrics] 
/// * [clearLyrics] - Remove the stored lyrics. Mutually exclusive with `lyrics`; sending both answers `invalid-request`. 
/// * [chapters] - A replacement chapter list for a book: ordered, non-overlapping, on the book timeline. An empty array restores the embedded chapters, as for `setBookChapters`. 
/// * [tagSets] - Custom tag key to its replacement values; empty values clear that tag. Applied in sorted key order, because a JSON object carries none of its own and the parts list has to be reproducible. 
/// * [tagRemoves] - Custom tag keys to remove, applied in the order given.
/// * [unofficial] - The release-status mark: true marks the item as having no canonical release, false clears the mark. Omitted leaves it alone. 
/// * [writeBack] - Also write the new values into the backing file's tags, for the parts that have a tag form (fields, credits, lyrics). 
/// * [lock] - Lock what each part wrote, against scans and enrichment. 
/// * [force] - Override existing locks.
@BuiltValue()
abstract class MetadataCommit implements Built<MetadataCommit, MetadataCommitBuilder> {
  /// Field name to new value; an empty string clears the field. Names come from the kind's vocabulary, as for `editItemMetadata`. 
  @BuiltValueField(wireName: r'fields')
  BuiltMap<String, String>? get fields;

  /// Replacement people per role, applied in the order given. 
  @BuiltValueField(wireName: r'credits')
  BuiltList<CommitCredits>? get credits;

  @BuiltValueField(wireName: r'lyrics')
  CommitLyrics? get lyrics;

  /// Remove the stored lyrics. Mutually exclusive with `lyrics`; sending both answers `invalid-request`. 
  @BuiltValueField(wireName: r'clearLyrics')
  bool? get clearLyrics;

  /// A replacement chapter list for a book: ordered, non-overlapping, on the book timeline. An empty array restores the embedded chapters, as for `setBookChapters`. 
  @BuiltValueField(wireName: r'chapters')
  BuiltList<ChapterMark>? get chapters;

  /// Custom tag key to its replacement values; empty values clear that tag. Applied in sorted key order, because a JSON object carries none of its own and the parts list has to be reproducible. 
  @BuiltValueField(wireName: r'tagSets')
  BuiltMap<String, BuiltList<String>>? get tagSets;

  /// Custom tag keys to remove, applied in the order given.
  @BuiltValueField(wireName: r'tagRemoves')
  BuiltList<String>? get tagRemoves;

  /// The release-status mark: true marks the item as having no canonical release, false clears the mark. Omitted leaves it alone. 
  @BuiltValueField(wireName: r'unofficial')
  bool? get unofficial;

  /// Also write the new values into the backing file's tags, for the parts that have a tag form (fields, credits, lyrics). 
  @BuiltValueField(wireName: r'writeBack')
  bool? get writeBack;

  /// Lock what each part wrote, against scans and enrichment. 
  @BuiltValueField(wireName: r'lock')
  bool? get lock;

  /// Override existing locks.
  @BuiltValueField(wireName: r'force')
  bool? get force;

  MetadataCommit._();

  factory MetadataCommit([void updates(MetadataCommitBuilder b)]) = _$MetadataCommit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MetadataCommitBuilder b) => b
      ..writeBack = false
      ..lock = true
      ..force = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<MetadataCommit> get serializer => _$MetadataCommitSerializer();
}

class _$MetadataCommitSerializer implements PrimitiveSerializer<MetadataCommit> {
  @override
  final Iterable<Type> types = const [MetadataCommit, _$MetadataCommit];

  @override
  final String wireName = r'MetadataCommit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MetadataCommit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.fields != null) {
      yield r'fields';
      yield serializers.serialize(
        object.fields,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
      );
    }
    if (object.credits != null) {
      yield r'credits';
      yield serializers.serialize(
        object.credits,
        specifiedType: const FullType(BuiltList, [FullType(CommitCredits)]),
      );
    }
    if (object.lyrics != null) {
      yield r'lyrics';
      yield serializers.serialize(
        object.lyrics,
        specifiedType: const FullType(CommitLyrics),
      );
    }
    if (object.clearLyrics != null) {
      yield r'clearLyrics';
      yield serializers.serialize(
        object.clearLyrics,
        specifiedType: const FullType(bool),
      );
    }
    if (object.chapters != null) {
      yield r'chapters';
      yield serializers.serialize(
        object.chapters,
        specifiedType: const FullType(BuiltList, [FullType(ChapterMark)]),
      );
    }
    if (object.tagSets != null) {
      yield r'tagSets';
      yield serializers.serialize(
        object.tagSets,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType(BuiltList, [FullType(String)])]),
      );
    }
    if (object.tagRemoves != null) {
      yield r'tagRemoves';
      yield serializers.serialize(
        object.tagRemoves,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.unofficial != null) {
      yield r'unofficial';
      yield serializers.serialize(
        object.unofficial,
        specifiedType: const FullType(bool),
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
    MetadataCommit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MetadataCommitBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'fields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(String)]),
          ) as BuiltMap<String, String>;
          result.fields.replace(valueDes);
          break;
        case r'credits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(CommitCredits)]),
          ) as BuiltList<CommitCredits>;
          result.credits.replace(valueDes);
          break;
        case r'lyrics':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CommitLyrics),
          ) as CommitLyrics;
          result.lyrics.replace(valueDes);
          break;
        case r'clearLyrics':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.clearLyrics = valueDes;
          break;
        case r'chapters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ChapterMark)]),
          ) as BuiltList<ChapterMark>;
          result.chapters.replace(valueDes);
          break;
        case r'tagSets':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(BuiltList, [FullType(String)])]),
          ) as BuiltMap<String, BuiltList<String>>;
          result.tagSets.replace(valueDes);
          break;
        case r'tagRemoves':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.tagRemoves.replace(valueDes);
          break;
        case r'unofficial':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.unofficial = valueDes;
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
  MetadataCommit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MetadataCommitBuilder();
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

