//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/smart_rule.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist.g.dart';

/// A playlist: a manual ordered list (`static`) or a rule evaluated per user on read (`smart`). `rule` is present only for smart playlists. `itemCount` is always the caller's own view of the membership: present and live for a static playlist, computed on detail reads and omitted from list pages for a smart one. 
///
/// Properties:
/// * [pid] - Type-prefixed ULID. Stable for the playlist's lifetime, including across rule edits. 
/// * [previousPid] - Retired. Rule edits once reissued the pid and set this to the retired one; edits now apply in place under a stable pid, so this is never populated. Retained for wire compatibility and always absent. 
/// * [name] - Display name.
/// * [kind] - `static` (manual ordered members) or `smart` (rule evaluated on read). A string, not a closed enum; clients must treat unknown kinds as read-only. 
/// * [visibility] - `private` (owner only) or `shared` (readable by every user). A string, not a closed enum. 
/// * [ownerName] - The owning user's display name.
/// * [isOwner] - True when the caller owns this playlist and may edit it.
/// * [hasArt] - A cover is stored for this playlist, readable at `/items/{pid}/art` with the playlist's own PID. It is true for an owner's uploaded cover and for the mosaic the server builds from the members when there is none; the two are the same slot, and uploading wins until it is cleared. Absent means false. 
/// * [itemCount] - How many members this caller is offered, which is what the member listing beside it returns: archived items, items in libraries the caller has no grant for, and episodes of unsubscribed shows are all out of it. Entries, not distinct items, so a static playlist holding one track twice counts it twice. Live and exact for a static playlist; computed for smart playlists on detail reads and absent on list pages. 
/// * [rule] 
/// * [createdAt] - When the playlist was created.
/// * [updatedAt] - When the playlist row last changed.
@BuiltValue()
abstract class Playlist implements Built<Playlist, PlaylistBuilder> {
  /// Type-prefixed ULID. Stable for the playlist's lifetime, including across rule edits. 
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Retired. Rule edits once reissued the pid and set this to the retired one; edits now apply in place under a stable pid, so this is never populated. Retained for wire compatibility and always absent. 
  @Deprecated('previousPid has been deprecated')
  @BuiltValueField(wireName: r'previousPid')
  String? get previousPid;

  /// Display name.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// `static` (manual ordered members) or `smart` (rule evaluated on read). A string, not a closed enum; clients must treat unknown kinds as read-only. 
  @BuiltValueField(wireName: r'kind')
  String get kind;

  /// `private` (owner only) or `shared` (readable by every user). A string, not a closed enum. 
  @BuiltValueField(wireName: r'visibility')
  String get visibility;

  /// The owning user's display name.
  @BuiltValueField(wireName: r'ownerName')
  String get ownerName;

  /// True when the caller owns this playlist and may edit it.
  @BuiltValueField(wireName: r'isOwner')
  bool get isOwner;

  /// A cover is stored for this playlist, readable at `/items/{pid}/art` with the playlist's own PID. It is true for an owner's uploaded cover and for the mosaic the server builds from the members when there is none; the two are the same slot, and uploading wins until it is cleared. Absent means false. 
  @BuiltValueField(wireName: r'hasArt')
  bool? get hasArt;

  /// How many members this caller is offered, which is what the member listing beside it returns: archived items, items in libraries the caller has no grant for, and episodes of unsubscribed shows are all out of it. Entries, not distinct items, so a static playlist holding one track twice counts it twice. Live and exact for a static playlist; computed for smart playlists on detail reads and absent on list pages. 
  @BuiltValueField(wireName: r'itemCount')
  int? get itemCount;

  @BuiltValueField(wireName: r'rule')
  SmartRule? get rule;

  /// When the playlist was created.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  /// When the playlist row last changed.
  @BuiltValueField(wireName: r'updatedAt')
  DateTime get updatedAt;

  Playlist._();

  factory Playlist([void updates(PlaylistBuilder b)]) = _$Playlist;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Playlist> get serializer => _$PlaylistSerializer();
}

class _$PlaylistSerializer implements PrimitiveSerializer<Playlist> {
  @override
  final Iterable<Type> types = const [Playlist, _$Playlist];

  @override
  final String wireName = r'Playlist';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Playlist object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    if (object.previousPid != null) {
      yield r'previousPid';
      yield serializers.serialize(
        object.previousPid,
        specifiedType: const FullType(String),
      );
    }
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(String),
    );
    yield r'visibility';
    yield serializers.serialize(
      object.visibility,
      specifiedType: const FullType(String),
    );
    yield r'ownerName';
    yield serializers.serialize(
      object.ownerName,
      specifiedType: const FullType(String),
    );
    yield r'isOwner';
    yield serializers.serialize(
      object.isOwner,
      specifiedType: const FullType(bool),
    );
    if (object.hasArt != null) {
      yield r'hasArt';
      yield serializers.serialize(
        object.hasArt,
        specifiedType: const FullType(bool),
      );
    }
    if (object.itemCount != null) {
      yield r'itemCount';
      yield serializers.serialize(
        object.itemCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.rule != null) {
      yield r'rule';
      yield serializers.serialize(
        object.rule,
        specifiedType: const FullType(SmartRule),
      );
    }
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'updatedAt';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Playlist object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistBuilder result,
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
        case r'previousPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.previousPid = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'visibility':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.visibility = valueDes;
          break;
        case r'ownerName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.ownerName = valueDes;
          break;
        case r'isOwner':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isOwner = valueDes;
          break;
        case r'hasArt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasArt = valueDes;
          break;
        case r'itemCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.itemCount = valueDes;
          break;
        case r'rule':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SmartRule),
          ) as SmartRule;
          result.rule.replace(valueDes);
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Playlist deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistBuilder();
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

