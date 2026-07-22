//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/resolve_rung_counts.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/playlist_import_miss.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_import_result.g.dart';

/// The import report.
///
/// Properties:
/// * [playlistPid] - The created playlist. Absent when nothing resolved (no playlist is created). 
/// * [name] - The playlist name used.
/// * [requested] - Entries found in the export.
/// * [resolved] - Entries matched to library items.
/// * [missing] - Entries with no library match, in export order: the missing-tracks report. 
/// * [rungs] 
@BuiltValue()
abstract class PlaylistImportResult implements Built<PlaylistImportResult, PlaylistImportResultBuilder> {
  /// The created playlist. Absent when nothing resolved (no playlist is created). 
  @BuiltValueField(wireName: r'playlistPid')
  String? get playlistPid;

  /// The playlist name used.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Entries found in the export.
  @BuiltValueField(wireName: r'requested')
  int get requested;

  /// Entries matched to library items.
  @BuiltValueField(wireName: r'resolved')
  int get resolved;

  /// Entries with no library match, in export order: the missing-tracks report. 
  @BuiltValueField(wireName: r'missing')
  BuiltList<PlaylistImportMiss> get missing;

  @BuiltValueField(wireName: r'rungs')
  ResolveRungCounts get rungs;

  PlaylistImportResult._();

  factory PlaylistImportResult([void updates(PlaylistImportResultBuilder b)]) = _$PlaylistImportResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistImportResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistImportResult> get serializer => _$PlaylistImportResultSerializer();
}

class _$PlaylistImportResultSerializer implements PrimitiveSerializer<PlaylistImportResult> {
  @override
  final Iterable<Type> types = const [PlaylistImportResult, _$PlaylistImportResult];

  @override
  final String wireName = r'PlaylistImportResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistImportResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.playlistPid != null) {
      yield r'playlistPid';
      yield serializers.serialize(
        object.playlistPid,
        specifiedType: const FullType(String),
      );
    }
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'requested';
    yield serializers.serialize(
      object.requested,
      specifiedType: const FullType(int),
    );
    yield r'resolved';
    yield serializers.serialize(
      object.resolved,
      specifiedType: const FullType(int),
    );
    yield r'missing';
    yield serializers.serialize(
      object.missing,
      specifiedType: const FullType(BuiltList, [FullType(PlaylistImportMiss)]),
    );
    yield r'rungs';
    yield serializers.serialize(
      object.rungs,
      specifiedType: const FullType(ResolveRungCounts),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaylistImportResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistImportResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'playlistPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.playlistPid = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'requested':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.requested = valueDes;
          break;
        case r'resolved':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.resolved = valueDes;
          break;
        case r'missing':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlaylistImportMiss)]),
          ) as BuiltList<PlaylistImportMiss>;
          result.missing.replace(valueDes);
          break;
        case r'rungs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ResolveRungCounts),
          ) as ResolveRungCounts;
          result.rungs.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaylistImportResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistImportResultBuilder();
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

