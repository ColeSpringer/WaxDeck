//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/candidate_summary.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_entry.g.dart';

/// One review queue entry: an album-sized unit of files awaiting or past a matching decision. The unit decides as a whole. 
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
@BuiltValue(instantiable: false)
abstract class ReviewEntry  {
  /// Entry pid.
  @BuiltValueField(wireName: r'id')
  String get id;

  /// What deciding does: `match` retags items already in the library; `import` additionally moves staged files (an upload or inbox batch) into the library. A string, not a closed enum. 
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// Lifecycle state: `pending`, `applied`, `auto-applied`, `as-is`, `unofficial`, `skipped`, `discarded`, or `reverted`. A string, not a closed enum. 
  @BuiltValueField(wireName: r'status')
  String get status;

  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  /// Where the unit came from: `scan`, `upload`, or `rematch`. A string, not a closed enum. 
  @BuiltValueField(wireName: r'origin')
  String get origin;

  /// Display title for the unit (the album guess).
  @BuiltValueField(wireName: r'title')
  String? get title;

  /// Display artist for the unit.
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// Files in the unit.
  @BuiltValueField(wireName: r'trackCount')
  int get trackCount;

  /// The library the unit belongs (or will import) to.
  @BuiltValueField(wireName: r'libraryPid')
  String? get libraryPid;

  /// The uploader's user pid, present on upload-origin entries. 
  @BuiltValueField(wireName: r'uploadedBy')
  String? get uploadedBy;

  /// True while the identify pipeline still runs for this entry; candidates and the best summary fill in when it finishes (the entry invalidates over the event channel). 
  @BuiltValueField(wireName: r'identifying')
  bool get identifying;

  @BuiltValueField(wireName: r'best')
  CandidateSummary? get best;

  /// The MusicBrainz release id an `applied` or `auto-applied` entry applied. 
  @BuiltValueField(wireName: r'appliedMbid')
  String? get appliedMbid;

  /// When the entry was created.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  /// When the entry was decided.
  @BuiltValueField(wireName: r'decidedAt')
  DateTime? get decidedAt;

  /// The deciding user's pid; absent on `auto-applied` entries. 
  @BuiltValueField(wireName: r'decidedBy')
  String? get decidedBy;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewEntry> get serializer => _$ReviewEntrySerializer();
}

class _$ReviewEntrySerializer implements PrimitiveSerializer<ReviewEntry> {
  @override
  final Iterable<Type> types = const [ReviewEntry];

  @override
  final String wireName = r'ReviewEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(String),
    );
    yield r'mediaType';
    yield serializers.serialize(
      object.mediaType,
      specifiedType: const FullType(MediaType),
    );
    yield r'origin';
    yield serializers.serialize(
      object.origin,
      specifiedType: const FullType(String),
    );
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType(String),
      );
    }
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    yield r'trackCount';
    yield serializers.serialize(
      object.trackCount,
      specifiedType: const FullType(int),
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
    yield r'identifying';
    yield serializers.serialize(
      object.identifying,
      specifiedType: const FullType(bool),
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
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.decidedAt != null) {
      yield r'decidedAt';
      yield serializers.serialize(
        object.decidedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.decidedBy != null) {
      yield r'decidedBy';
      yield serializers.serialize(
        object.decidedBy,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  ReviewEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($ReviewEntry)) as $ReviewEntry;
  }
}

/// a concrete implementation of [ReviewEntry], since [ReviewEntry] is not instantiable
@BuiltValue(instantiable: true)
abstract class $ReviewEntry implements ReviewEntry, Built<$ReviewEntry, $ReviewEntryBuilder> {
  $ReviewEntry._();

  factory $ReviewEntry([void Function($ReviewEntryBuilder)? updates]) = _$$ReviewEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($ReviewEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$ReviewEntry> get serializer => _$$ReviewEntrySerializer();
}

class _$$ReviewEntrySerializer implements PrimitiveSerializer<$ReviewEntry> {
  @override
  final Iterable<Type> types = const [$ReviewEntry, _$$ReviewEntry];

  @override
  final String wireName = r'$ReviewEntry';

  @override
  Object serialize(
    Serializers serializers,
    $ReviewEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(ReviewEntry))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.status = valueDes;
          break;
        case r'mediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaType),
          ) as MediaType;
          result.mediaType = valueDes;
          break;
        case r'origin':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.origin = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'artist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artist = valueDes;
          break;
        case r'trackCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.trackCount = valueDes;
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
        case r'identifying':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.identifying = valueDes;
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
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'decidedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.decidedAt = valueDes;
          break;
        case r'decidedBy':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.decidedBy = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  $ReviewEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $ReviewEntryBuilder();
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

