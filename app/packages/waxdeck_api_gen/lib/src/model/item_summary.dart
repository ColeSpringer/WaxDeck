//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item_summary.g.dart';

/// Compact item representation used by list endpoints and client-side library mirrors (~summary row). 
///
/// Properties:
/// * [pid] - Type-prefixed ULID.
/// * [mediaType] 
/// * [title] - Display title.
/// * [artist] - Primary display artist / author / show name.
/// * [album] - Album / series / podcast title, when applicable.
/// * [artistPid] - The artist entity behind `artist`, so a client can group and link by identity rather than by display text - two artists with the same name are two entities, and one artist spelled two ways is still one. Absent when the item has no artist entity. For an audiobook this is its author. 
/// * [albumPid] - The album entity behind `album`, for the same reason. Tracks only: a podcast episode and an audiobook are not album members, and their `album` is a series or show title with no album entity behind it. Absent when the track belongs to no album. 
/// * [trackNumber] - Track position within its disc (music). On the summary row rather than only on the detail because a listing is where it is needed: an album's items page arrives in the library's own stable order, and this plus `discNumber` is what a client sorts a release back into. Absent when the item carries none. 
/// * [discNumber] - Disc number within a multi-disc release (music). Absent for a single-disc release and for anything that is not a track. 
/// * [durationMs] - Duration in milliseconds. For a multi-file audiobook this is the total across all parts; for a not-yet-fetched podcast episode it is the feed-declared duration, or 0 when the feed declares none. 
/// * [artUrl] - Origin-relative URL of the item's artwork endpoint. Always populated; the endpoint itself returns 404 for items with no artwork, so clients keep a placeholder ready. 
@BuiltValue(instantiable: false)
abstract class ItemSummary  {
  /// Type-prefixed ULID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  /// Display title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Primary display artist / author / show name.
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// Album / series / podcast title, when applicable.
  @BuiltValueField(wireName: r'album')
  String? get album;

  /// The artist entity behind `artist`, so a client can group and link by identity rather than by display text - two artists with the same name are two entities, and one artist spelled two ways is still one. Absent when the item has no artist entity. For an audiobook this is its author. 
  @BuiltValueField(wireName: r'artistPid')
  String? get artistPid;

  /// The album entity behind `album`, for the same reason. Tracks only: a podcast episode and an audiobook are not album members, and their `album` is a series or show title with no album entity behind it. Absent when the track belongs to no album. 
  @BuiltValueField(wireName: r'albumPid')
  String? get albumPid;

  /// Track position within its disc (music). On the summary row rather than only on the detail because a listing is where it is needed: an album's items page arrives in the library's own stable order, and this plus `discNumber` is what a client sorts a release back into. Absent when the item carries none. 
  @BuiltValueField(wireName: r'trackNumber')
  int? get trackNumber;

  /// Disc number within a multi-disc release (music). Absent for a single-disc release and for anything that is not a track. 
  @BuiltValueField(wireName: r'discNumber')
  int? get discNumber;

  /// Duration in milliseconds. For a multi-file audiobook this is the total across all parts; for a not-yet-fetched podcast episode it is the feed-declared duration, or 0 when the feed declares none. 
  @BuiltValueField(wireName: r'durationMs')
  int get durationMs;

  /// Origin-relative URL of the item's artwork endpoint. Always populated; the endpoint itself returns 404 for items with no artwork, so clients keep a placeholder ready. 
  @BuiltValueField(wireName: r'artUrl')
  String? get artUrl;

  @BuiltValueSerializer(custom: true)
  static Serializer<ItemSummary> get serializer => _$ItemSummarySerializer();
}

class _$ItemSummarySerializer implements PrimitiveSerializer<ItemSummary> {
  @override
  final Iterable<Type> types = const [ItemSummary];

  @override
  final String wireName = r'ItemSummary';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ItemSummary object, {
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
    if (object.album != null) {
      yield r'album';
      yield serializers.serialize(
        object.album,
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
    if (object.albumPid != null) {
      yield r'albumPid';
      yield serializers.serialize(
        object.albumPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.trackNumber != null) {
      yield r'trackNumber';
      yield serializers.serialize(
        object.trackNumber,
        specifiedType: const FullType(int),
      );
    }
    if (object.discNumber != null) {
      yield r'discNumber';
      yield serializers.serialize(
        object.discNumber,
        specifiedType: const FullType(int),
      );
    }
    yield r'durationMs';
    yield serializers.serialize(
      object.durationMs,
      specifiedType: const FullType(int),
    );
    if (object.artUrl != null) {
      yield r'artUrl';
      yield serializers.serialize(
        object.artUrl,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ItemSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  ItemSummary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($ItemSummary)) as $ItemSummary;
  }
}

/// a concrete implementation of [ItemSummary], since [ItemSummary] is not instantiable
@BuiltValue(instantiable: true)
abstract class $ItemSummary implements ItemSummary, Built<$ItemSummary, $ItemSummaryBuilder> {
  $ItemSummary._();

  factory $ItemSummary([void Function($ItemSummaryBuilder)? updates]) = _$$ItemSummary;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($ItemSummaryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$ItemSummary> get serializer => _$$ItemSummarySerializer();
}

class _$$ItemSummarySerializer implements PrimitiveSerializer<$ItemSummary> {
  @override
  final Iterable<Type> types = const [$ItemSummary, _$$ItemSummary];

  @override
  final String wireName = r'$ItemSummary';

  @override
  Object serialize(
    Serializers serializers,
    $ItemSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(ItemSummary))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ItemSummaryBuilder result,
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
        case r'album':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.album = valueDes;
          break;
        case r'artistPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artistPid = valueDes;
          break;
        case r'albumPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.albumPid = valueDes;
          break;
        case r'trackNumber':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.trackNumber = valueDes;
          break;
        case r'discNumber':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.discNumber = valueDes;
          break;
        case r'durationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMs = valueDes;
          break;
        case r'artUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  $ItemSummary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $ItemSummaryBuilder();
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

