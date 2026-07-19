//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/playlist_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_items_page.g.dart';

/// One page of playlist members.
///
/// Properties:
/// * [entries] - Members in playlist order.
/// * [nextCursor] - Opaque cursor for the next page. Absent on the last page.
@BuiltValue()
abstract class PlaylistItemsPage implements Built<PlaylistItemsPage, PlaylistItemsPageBuilder> {
  /// Members in playlist order.
  @BuiltValueField(wireName: r'entries')
  BuiltList<PlaylistEntry> get entries;

  /// Opaque cursor for the next page. Absent on the last page.
  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  PlaylistItemsPage._();

  factory PlaylistItemsPage([void updates(PlaylistItemsPageBuilder b)]) = _$PlaylistItemsPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistItemsPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistItemsPage> get serializer => _$PlaylistItemsPageSerializer();
}

class _$PlaylistItemsPageSerializer implements PrimitiveSerializer<PlaylistItemsPage> {
  @override
  final Iterable<Type> types = const [PlaylistItemsPage, _$PlaylistItemsPage];

  @override
  final String wireName = r'PlaylistItemsPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistItemsPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(PlaylistEntry)]),
    );
    if (object.nextCursor != null) {
      yield r'nextCursor';
      yield serializers.serialize(
        object.nextCursor,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaylistItemsPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistItemsPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlaylistEntry)]),
          ) as BuiltList<PlaylistEntry>;
          result.entries.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nextCursor = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaylistItemsPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistItemsPageBuilder();
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

