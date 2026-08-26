//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_sync_counts.g.dart';

/// One completed sync run's counts.
///
/// Properties:
/// * [added] - Members the run attached.
/// * [removed] - Members the run removed.
/// * [trashed] - Files the run moved to the trash.
/// * [queued] - Downloads the run queued.
/// * [unavailable] - Entries the source reported unavailable.
/// * [missing] - Matched-source refs with no library match. 
@BuiltValue()
abstract class PlaylistSyncCounts implements Built<PlaylistSyncCounts, PlaylistSyncCountsBuilder> {
  /// Members the run attached.
  @BuiltValueField(wireName: r'added')
  int get added;

  /// Members the run removed.
  @BuiltValueField(wireName: r'removed')
  int get removed;

  /// Files the run moved to the trash.
  @BuiltValueField(wireName: r'trashed')
  int get trashed;

  /// Downloads the run queued.
  @BuiltValueField(wireName: r'queued')
  int get queued;

  /// Entries the source reported unavailable.
  @BuiltValueField(wireName: r'unavailable')
  int get unavailable;

  /// Matched-source refs with no library match. 
  @BuiltValueField(wireName: r'missing')
  int get missing;

  PlaylistSyncCounts._();

  factory PlaylistSyncCounts([void updates(PlaylistSyncCountsBuilder b)]) = _$PlaylistSyncCounts;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistSyncCountsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistSyncCounts> get serializer => _$PlaylistSyncCountsSerializer();
}

class _$PlaylistSyncCountsSerializer implements PrimitiveSerializer<PlaylistSyncCounts> {
  @override
  final Iterable<Type> types = const [PlaylistSyncCounts, _$PlaylistSyncCounts];

  @override
  final String wireName = r'PlaylistSyncCounts';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistSyncCounts object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'added';
    yield serializers.serialize(
      object.added,
      specifiedType: const FullType(int),
    );
    yield r'removed';
    yield serializers.serialize(
      object.removed,
      specifiedType: const FullType(int),
    );
    yield r'trashed';
    yield serializers.serialize(
      object.trashed,
      specifiedType: const FullType(int),
    );
    yield r'queued';
    yield serializers.serialize(
      object.queued,
      specifiedType: const FullType(int),
    );
    yield r'unavailable';
    yield serializers.serialize(
      object.unavailable,
      specifiedType: const FullType(int),
    );
    yield r'missing';
    yield serializers.serialize(
      object.missing,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaylistSyncCounts object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistSyncCountsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'added':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.added = valueDes;
          break;
        case r'removed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.removed = valueDes;
          break;
        case r'trashed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.trashed = valueDes;
          break;
        case r'queued':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.queued = valueDes;
          break;
        case r'unavailable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.unavailable = valueDes;
          break;
        case r'missing':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.missing = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaylistSyncCounts deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistSyncCountsBuilder();
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

