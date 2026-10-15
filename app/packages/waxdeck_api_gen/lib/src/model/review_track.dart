//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/duplicate_warning.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_track.g.dart';

/// One file in a review unit with its current metadata.
///
/// Properties:
/// * [pid] - The catalog item pid, type-prefixed like every pid on this API; absent for staged files that have not entered the library yet, and for a joined file whose item sits where the caller cannot see it. 
/// * [path] - The file's name. Administrators get the full path of a file a scan or rematch entry names; an uploaded or downloaded file is named alone for everyone, before it lands and after. 
/// * [title] - Current title (tag, or cleaned filename).
/// * [artist] - Current artist.
/// * [trackNo] - Current track number, 0 when untagged.
/// * [discNo] - Current disc number, 0 when untagged.
/// * [durationMs] - Audio length in milliseconds.
/// * [duplicate] 
/// * [joined] - The file entered the library as a copy of, or a further part of, an item that already existed; that item's metadata and who may edit it were not touched. 
@BuiltValue()
abstract class ReviewTrack implements Built<ReviewTrack, ReviewTrackBuilder> {
  /// The catalog item pid, type-prefixed like every pid on this API; absent for staged files that have not entered the library yet, and for a joined file whose item sits where the caller cannot see it. 
  @BuiltValueField(wireName: r'pid')
  String? get pid;

  /// The file's name. Administrators get the full path of a file a scan or rematch entry names; an uploaded or downloaded file is named alone for everyone, before it lands and after. 
  @BuiltValueField(wireName: r'path')
  String get path;

  /// Current title (tag, or cleaned filename).
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Current artist.
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// Current track number, 0 when untagged.
  @BuiltValueField(wireName: r'trackNo')
  int? get trackNo;

  /// Current disc number, 0 when untagged.
  @BuiltValueField(wireName: r'discNo')
  int? get discNo;

  /// Audio length in milliseconds.
  @BuiltValueField(wireName: r'durationMs')
  int get durationMs;

  @BuiltValueField(wireName: r'duplicate')
  DuplicateWarning? get duplicate;

  /// The file entered the library as a copy of, or a further part of, an item that already existed; that item's metadata and who may edit it were not touched. 
  @BuiltValueField(wireName: r'joined')
  bool? get joined;

  ReviewTrack._();

  factory ReviewTrack([void updates(ReviewTrackBuilder b)]) = _$ReviewTrack;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewTrackBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewTrack> get serializer => _$ReviewTrackSerializer();
}

class _$ReviewTrackSerializer implements PrimitiveSerializer<ReviewTrack> {
  @override
  final Iterable<Type> types = const [ReviewTrack, _$ReviewTrack];

  @override
  final String wireName = r'ReviewTrack';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewTrack object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.pid != null) {
      yield r'pid';
      yield serializers.serialize(
        object.pid,
        specifiedType: const FullType(String),
      );
    }
    yield r'path';
    yield serializers.serialize(
      object.path,
      specifiedType: const FullType(String),
    );
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    if (object.trackNo != null) {
      yield r'trackNo';
      yield serializers.serialize(
        object.trackNo,
        specifiedType: const FullType(int),
      );
    }
    if (object.discNo != null) {
      yield r'discNo';
      yield serializers.serialize(
        object.discNo,
        specifiedType: const FullType(int),
      );
    }
    yield r'durationMs';
    yield serializers.serialize(
      object.durationMs,
      specifiedType: const FullType(int),
    );
    if (object.duplicate != null) {
      yield r'duplicate';
      yield serializers.serialize(
        object.duplicate,
        specifiedType: const FullType(DuplicateWarning),
      );
    }
    if (object.joined != null) {
      yield r'joined';
      yield serializers.serialize(
        object.joined,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewTrack object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewTrackBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.pid = valueDes;
          break;
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.path = valueDes;
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
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.artist = valueDes;
          break;
        case r'trackNo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.trackNo = valueDes;
          break;
        case r'discNo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.discNo = valueDes;
          break;
        case r'durationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMs = valueDes;
          break;
        case r'duplicate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DuplicateWarning),
          ) as DuplicateWarning?;
          if (valueDes == null) continue;
          result.duplicate.replace(valueDes);
          break;
        case r'joined':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.joined = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReviewTrack deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewTrackBuilder();
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


