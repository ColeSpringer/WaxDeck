//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/playlist_import_miss.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_sync_preview.g.dart';

/// What a sync would do right now, computed by the same reconciler without writing anything. 
///
/// Properties:
/// * [entries] - Entries enumerated from the source, or refs a matched binding holds. 
/// * [wouldAdd] - Members a sync would attach now.
/// * [wouldDownload] - New entries a sync would queue downloads for; they join the playlist once their review entries resolve. 
/// * [wouldRemove] - Members a sync would remove.
/// * [wouldTrash] - Files a sync would move to the recoverable trash (`mirror-trash` only, always at most `wouldRemove`). 
/// * [pending] - Entries already downloading or waiting in the review queue. 
/// * [unavailable] - Entries the source reports unavailable, best-effort from what enumeration inspected. 
/// * [missing] - Matched-source refs with no library match.
/// * [misses] - The unmatched refs themselves, in source order. Matched bindings only. 
@BuiltValue()
abstract class PlaylistSyncPreview implements Built<PlaylistSyncPreview, PlaylistSyncPreviewBuilder> {
  /// Entries enumerated from the source, or refs a matched binding holds. 
  @BuiltValueField(wireName: r'entries')
  int get entries;

  /// Members a sync would attach now.
  @BuiltValueField(wireName: r'wouldAdd')
  int get wouldAdd;

  /// New entries a sync would queue downloads for; they join the playlist once their review entries resolve. 
  @BuiltValueField(wireName: r'wouldDownload')
  int get wouldDownload;

  /// Members a sync would remove.
  @BuiltValueField(wireName: r'wouldRemove')
  int get wouldRemove;

  /// Files a sync would move to the recoverable trash (`mirror-trash` only, always at most `wouldRemove`). 
  @BuiltValueField(wireName: r'wouldTrash')
  int get wouldTrash;

  /// Entries already downloading or waiting in the review queue. 
  @BuiltValueField(wireName: r'pending')
  int get pending;

  /// Entries the source reports unavailable, best-effort from what enumeration inspected. 
  @BuiltValueField(wireName: r'unavailable')
  int get unavailable;

  /// Matched-source refs with no library match.
  @BuiltValueField(wireName: r'missing')
  int get missing;

  /// The unmatched refs themselves, in source order. Matched bindings only. 
  @BuiltValueField(wireName: r'misses')
  BuiltList<PlaylistImportMiss>? get misses;

  PlaylistSyncPreview._();

  factory PlaylistSyncPreview([void updates(PlaylistSyncPreviewBuilder b)]) = _$PlaylistSyncPreview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistSyncPreviewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistSyncPreview> get serializer => _$PlaylistSyncPreviewSerializer();
}

class _$PlaylistSyncPreviewSerializer implements PrimitiveSerializer<PlaylistSyncPreview> {
  @override
  final Iterable<Type> types = const [PlaylistSyncPreview, _$PlaylistSyncPreview];

  @override
  final String wireName = r'PlaylistSyncPreview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistSyncPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(int),
    );
    yield r'wouldAdd';
    yield serializers.serialize(
      object.wouldAdd,
      specifiedType: const FullType(int),
    );
    yield r'wouldDownload';
    yield serializers.serialize(
      object.wouldDownload,
      specifiedType: const FullType(int),
    );
    yield r'wouldRemove';
    yield serializers.serialize(
      object.wouldRemove,
      specifiedType: const FullType(int),
    );
    yield r'wouldTrash';
    yield serializers.serialize(
      object.wouldTrash,
      specifiedType: const FullType(int),
    );
    yield r'pending';
    yield serializers.serialize(
      object.pending,
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
    if (object.misses != null) {
      yield r'misses';
      yield serializers.serialize(
        object.misses,
        specifiedType: const FullType(BuiltList, [FullType(PlaylistImportMiss)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaylistSyncPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistSyncPreviewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.entries = valueDes;
          break;
        case r'wouldAdd':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.wouldAdd = valueDes;
          break;
        case r'wouldDownload':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.wouldDownload = valueDes;
          break;
        case r'wouldRemove':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.wouldRemove = valueDes;
          break;
        case r'wouldTrash':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.wouldTrash = valueDes;
          break;
        case r'pending':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.pending = valueDes;
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
        case r'misses':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlaylistImportMiss)]),
          ) as BuiltList<PlaylistImportMiss>;
          result.misses.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaylistSyncPreview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistSyncPreviewBuilder();
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

