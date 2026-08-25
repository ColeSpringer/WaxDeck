//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/review_track.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/review_entry.dart';
import 'package:waxdeck_api_gen/src/model/review_candidate.dart';
import 'package:waxdeck_api_gen/src/model/review_identify_request.dart';
import 'package:waxdeck_api_gen/src/model/candidate_summary.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_entry_detail.g.dart';

/// One review entry with its full evidence.
///
/// Properties:
/// * [id] - Entry pid.
/// * [kind] - What deciding does: `match` retags items already in the library; `import` additionally moves staged files (an upload or inbox batch) into the library. A string, not a closed enum. 
/// * [status] - Lifecycle state: `pending`, `applied`, `auto-applied`, `as-is`, `unofficial`, `skipped`, `discarded`, or `reverted`. A string, not a closed enum. 
/// * [mediaType] 
/// * [origin] - Where the unit came from: `scan`, `upload`, or `rematch`. A string, not a closed enum. 
/// * [title] - Display title for the unit (the album guess).
/// * [artist] - Display artist for the unit.
/// * [trackCount] - Files in the unit.
/// * [libraryPid] - The library the unit belongs (or will import) to.
/// * [uploadedBy] - The uploader's user pid, present on upload-origin entries. 
/// * [identifying] - True while the identify pipeline still runs for this entry; candidates and the best summary fill in when it finishes (the entry invalidates over the event channel). 
/// * [best] 
/// * [appliedMbid] - The MusicBrainz release id an `applied` or `auto-applied` entry applied. 
/// * [createdAt] - When the entry was created.
/// * [decidedAt] - When the entry was decided.
/// * [decidedBy] - The deciding user's pid; absent on `auto-applied` entries. 
/// * [tracks] - The unit's files in disc and track order.
/// * [candidates] - Scored candidates, ranked best first. For a one-file unit, near-tied candidates are ordered by preference (header agreement, then a plain release over a compilation), so the list is not strictly sorted by `similarityPct` inside a tie band. 
/// * [identifyDeclined] - The submission asked not to be identified, so the entry never entered the match queue. Absent means it did. What it tells a reader is why `candidates` is empty: nothing was searched, rather than searched and found nothing.  Such an entry is normally already `as-is` - declining imports the files without stopping. Finding one still `pending` means the automatic import could not proceed and it is waiting for a person. 
/// * [identifyOverride] - What the last re-identify searched for in place of the files' own tags. Absent when nothing was typed. The `tracks` below always report the tags the files carry, never this.  Not named `override`: the Dart generator emits a property name verbatim, and `override` there collides with the language's own annotation. 
/// * [suggested] - What the matching parse read out of the source's own title, offered as a starting point for a search rather than as a claim about the files. Present only on acquisitions of a single loose file, where the title is a video title and the artist tag is a channel; an album-shaped unit carries real tags and needs no guess. Never an album, since a loose track has none. A stored `identifyOverride` supersedes it. 
@BuiltValue()
abstract class ReviewEntryDetail implements ReviewEntry, Built<ReviewEntryDetail, ReviewEntryDetailBuilder> {
  /// Scored candidates, ranked best first. For a one-file unit, near-tied candidates are ordered by preference (header agreement, then a plain release over a compilation), so the list is not strictly sorted by `similarityPct` inside a tie band. 
  @BuiltValueField(wireName: r'candidates')
  BuiltList<ReviewCandidate> get candidates;

  /// What the matching parse read out of the source's own title, offered as a starting point for a search rather than as a claim about the files. Present only on acquisitions of a single loose file, where the title is a video title and the artist tag is a channel; an album-shaped unit carries real tags and needs no guess. Never an album, since a loose track has none. A stored `identifyOverride` supersedes it. 
  @BuiltValueField(wireName: r'suggested')
  ReviewIdentifyRequest? get suggested;

  /// What the last re-identify searched for in place of the files' own tags. Absent when nothing was typed. The `tracks` below always report the tags the files carry, never this.  Not named `override`: the Dart generator emits a property name verbatim, and `override` there collides with the language's own annotation. 
  @BuiltValueField(wireName: r'identifyOverride')
  ReviewIdentifyRequest? get identifyOverride;

  /// The submission asked not to be identified, so the entry never entered the match queue. Absent means it did. What it tells a reader is why `candidates` is empty: nothing was searched, rather than searched and found nothing.  Such an entry is normally already `as-is` - declining imports the files without stopping. Finding one still `pending` means the automatic import could not proceed and it is waiting for a person. 
  @BuiltValueField(wireName: r'identifyDeclined')
  bool? get identifyDeclined;

  /// The unit's files in disc and track order.
  @BuiltValueField(wireName: r'tracks')
  BuiltList<ReviewTrack> get tracks;

  ReviewEntryDetail._();

  factory ReviewEntryDetail([void updates(ReviewEntryDetailBuilder b)]) = _$ReviewEntryDetail;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewEntryDetailBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewEntryDetail> get serializer => _$ReviewEntryDetailSerializer();
}

class _$ReviewEntryDetailSerializer implements PrimitiveSerializer<ReviewEntryDetail> {
  @override
  final Iterable<Type> types = const [ReviewEntryDetail, _$ReviewEntryDetail];

  @override
  final String wireName = r'ReviewEntryDetail';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewEntryDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'identifying';
    yield serializers.serialize(
      object.identifying,
      specifiedType: const FullType(bool),
    );
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    yield r'origin';
    yield serializers.serialize(
      object.origin,
      specifiedType: const FullType(String),
    );
    if (object.identifyOverride != null) {
      yield r'identifyOverride';
      yield serializers.serialize(
        object.identifyOverride,
        specifiedType: const FullType(ReviewIdentifyRequest),
      );
    }
    yield r'mediaType';
    yield serializers.serialize(
      object.mediaType,
      specifiedType: const FullType(MediaType),
    );
    if (object.best != null) {
      yield r'best';
      yield serializers.serialize(
        object.best,
        specifiedType: const FullType(CandidateSummary),
      );
    }
    if (object.appliedMbid != null) {
      yield r'appliedMbid';
      yield serializers.serialize(
        object.appliedMbid,
        specifiedType: const FullType(String),
      );
    }
    if (object.decidedBy != null) {
      yield r'decidedBy';
      yield serializers.serialize(
        object.decidedBy,
        specifiedType: const FullType(String),
      );
    }
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType(String),
      );
    }
    if (object.identifyDeclined != null) {
      yield r'identifyDeclined';
      yield serializers.serialize(
        object.identifyDeclined,
        specifiedType: const FullType(bool),
      );
    }
    yield r'tracks';
    yield serializers.serialize(
      object.tracks,
      specifiedType: const FullType(BuiltList, [FullType(ReviewTrack)]),
    );
    yield r'candidates';
    yield serializers.serialize(
      object.candidates,
      specifiedType: const FullType(BuiltList, [FullType(ReviewCandidate)]),
    );
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.suggested != null) {
      yield r'suggested';
      yield serializers.serialize(
        object.suggested,
        specifiedType: const FullType(ReviewIdentifyRequest),
      );
    }
    yield r'trackCount';
    yield serializers.serialize(
      object.trackCount,
      specifiedType: const FullType(int),
    );
    if (object.decidedAt != null) {
      yield r'decidedAt';
      yield serializers.serialize(
        object.decidedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    if (object.libraryPid != null) {
      yield r'libraryPid';
      yield serializers.serialize(
        object.libraryPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.uploadedBy != null) {
      yield r'uploadedBy';
      yield serializers.serialize(
        object.uploadedBy,
        specifiedType: const FullType(String),
      );
    }
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewEntryDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewEntryDetailBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'identifying':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.identifying = valueDes;
          break;
        case r'artist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artist = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'origin':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.origin = valueDes;
          break;
        case r'identifyOverride':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReviewIdentifyRequest),
          ) as ReviewIdentifyRequest;
          result.identifyOverride.replace(valueDes);
          break;
        case r'mediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaType),
          ) as MediaType;
          result.mediaType = valueDes;
          break;
        case r'best':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CandidateSummary),
          ) as CandidateSummary;
          result.best.replace(valueDes);
          break;
        case r'appliedMbid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.appliedMbid = valueDes;
          break;
        case r'decidedBy':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.decidedBy = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'identifyDeclined':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.identifyDeclined = valueDes;
          break;
        case r'tracks':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ReviewTrack)]),
          ) as BuiltList<ReviewTrack>;
          result.tracks.replace(valueDes);
          break;
        case r'candidates':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ReviewCandidate)]),
          ) as BuiltList<ReviewCandidate>;
          result.candidates.replace(valueDes);
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'suggested':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReviewIdentifyRequest),
          ) as ReviewIdentifyRequest;
          result.suggested.replace(valueDes);
          break;
        case r'trackCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.trackCount = valueDes;
          break;
        case r'decidedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.decidedAt = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'libraryPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.libraryPid = valueDes;
          break;
        case r'uploadedBy':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.uploadedBy = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.status = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReviewEntryDetail deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewEntryDetailBuilder();
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

