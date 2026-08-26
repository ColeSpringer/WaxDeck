//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/playlist_sync_counts.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_source.g.dart';

/// A playlist's external source binding: what it follows, how, and how the syncing has been going. 
///
/// Properties:
/// * [source_] - Where the members come from: `youtube` for a live URL binding, else the import source the binding was recorded from (`spotify`, `applemusic`, `ytmusic`, `csv`, `text`, `portable`). A string, not a closed enum; clients must treat unknown sources as opaque labels. 
/// * [url] - The source playlist's URL. Live bindings only.
/// * [title] - The source playlist's own title, as last enumerated. Live bindings only. 
/// * [live] - True when the server can re-fetch the source itself: the binding syncs on the stored interval and downloads new entries. False for a matched source, which reconciles match-only and on demand. 
/// * [mode] - `append` (add new entries, manual edits preserved), `mirror` (membership and order follow the source, a removed entry's file stays in the library), or `mirror-trash` (mirror, and a removed entry's file goes to the recoverable trash). 
/// * [intervalHours] - Hours between scheduled runs. Live bindings only.
/// * [refCount] - Portable refs the binding stores. Matched bindings only. 
/// * [disabled] - True when scheduled syncing was suspended after repeated failures. A successful manual sync re-enables it. 
/// * [consecutiveFailures] - Failed runs since the last success.
/// * [lastError] - Why the last failing run failed.
/// * [lastAttemptAt] - When a run last started, successful or not.
/// * [lastSyncedAt] - When a run last completed successfully.
/// * [lastRun] 
@BuiltValue()
abstract class PlaylistSource implements Built<PlaylistSource, PlaylistSourceBuilder> {
  /// Where the members come from: `youtube` for a live URL binding, else the import source the binding was recorded from (`spotify`, `applemusic`, `ytmusic`, `csv`, `text`, `portable`). A string, not a closed enum; clients must treat unknown sources as opaque labels. 
  @BuiltValueField(wireName: r'source')
  String get source_;

  /// The source playlist's URL. Live bindings only.
  @BuiltValueField(wireName: r'url')
  String? get url;

  /// The source playlist's own title, as last enumerated. Live bindings only. 
  @BuiltValueField(wireName: r'title')
  String? get title;

  /// True when the server can re-fetch the source itself: the binding syncs on the stored interval and downloads new entries. False for a matched source, which reconciles match-only and on demand. 
  @BuiltValueField(wireName: r'live')
  bool get live;

  /// `append` (add new entries, manual edits preserved), `mirror` (membership and order follow the source, a removed entry's file stays in the library), or `mirror-trash` (mirror, and a removed entry's file goes to the recoverable trash). 
  @BuiltValueField(wireName: r'mode')
  String get mode;

  /// Hours between scheduled runs. Live bindings only.
  @BuiltValueField(wireName: r'intervalHours')
  int? get intervalHours;

  /// Portable refs the binding stores. Matched bindings only. 
  @BuiltValueField(wireName: r'refCount')
  int? get refCount;

  /// True when scheduled syncing was suspended after repeated failures. A successful manual sync re-enables it. 
  @BuiltValueField(wireName: r'disabled')
  bool get disabled;

  /// Failed runs since the last success.
  @BuiltValueField(wireName: r'consecutiveFailures')
  int get consecutiveFailures;

  /// Why the last failing run failed.
  @BuiltValueField(wireName: r'lastError')
  String? get lastError;

  /// When a run last started, successful or not.
  @BuiltValueField(wireName: r'lastAttemptAt')
  DateTime? get lastAttemptAt;

  /// When a run last completed successfully.
  @BuiltValueField(wireName: r'lastSyncedAt')
  DateTime? get lastSyncedAt;

  @BuiltValueField(wireName: r'lastRun')
  PlaylistSyncCounts? get lastRun;

  PlaylistSource._();

  factory PlaylistSource([void updates(PlaylistSourceBuilder b)]) = _$PlaylistSource;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistSourceBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistSource> get serializer => _$PlaylistSourceSerializer();
}

class _$PlaylistSourceSerializer implements PrimitiveSerializer<PlaylistSource> {
  @override
  final Iterable<Type> types = const [PlaylistSource, _$PlaylistSource];

  @override
  final String wireName = r'PlaylistSource';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistSource object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(String),
    );
    if (object.url != null) {
      yield r'url';
      yield serializers.serialize(
        object.url,
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
    yield r'live';
    yield serializers.serialize(
      object.live,
      specifiedType: const FullType(bool),
    );
    yield r'mode';
    yield serializers.serialize(
      object.mode,
      specifiedType: const FullType(String),
    );
    if (object.intervalHours != null) {
      yield r'intervalHours';
      yield serializers.serialize(
        object.intervalHours,
        specifiedType: const FullType(int),
      );
    }
    if (object.refCount != null) {
      yield r'refCount';
      yield serializers.serialize(
        object.refCount,
        specifiedType: const FullType(int),
      );
    }
    yield r'disabled';
    yield serializers.serialize(
      object.disabled,
      specifiedType: const FullType(bool),
    );
    yield r'consecutiveFailures';
    yield serializers.serialize(
      object.consecutiveFailures,
      specifiedType: const FullType(int),
    );
    if (object.lastError != null) {
      yield r'lastError';
      yield serializers.serialize(
        object.lastError,
        specifiedType: const FullType(String),
      );
    }
    if (object.lastAttemptAt != null) {
      yield r'lastAttemptAt';
      yield serializers.serialize(
        object.lastAttemptAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.lastSyncedAt != null) {
      yield r'lastSyncedAt';
      yield serializers.serialize(
        object.lastSyncedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.lastRun != null) {
      yield r'lastRun';
      yield serializers.serialize(
        object.lastRun,
        specifiedType: const FullType(PlaylistSyncCounts),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaylistSource object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistSourceBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.source_ = valueDes;
          break;
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'live':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.live = valueDes;
          break;
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mode = valueDes;
          break;
        case r'intervalHours':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.intervalHours = valueDes;
          break;
        case r'refCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.refCount = valueDes;
          break;
        case r'disabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.disabled = valueDes;
          break;
        case r'consecutiveFailures':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.consecutiveFailures = valueDes;
          break;
        case r'lastError':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastError = valueDes;
          break;
        case r'lastAttemptAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastAttemptAt = valueDes;
          break;
        case r'lastSyncedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastSyncedAt = valueDes;
          break;
        case r'lastRun':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlaylistSyncCounts),
          ) as PlaylistSyncCounts;
          result.lastRun.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaylistSource deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistSourceBuilder();
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

