//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_entry.g.dart';

/// One playlist member.
///
/// Properties:
/// * [position] - Zero-based position in the stored member order. Present only for static playlists; this is the value the removal endpoint takes. 
/// * [item] 
@BuiltValue()
abstract class PlaylistEntry implements Built<PlaylistEntry, PlaylistEntryBuilder> {
  /// Zero-based position in the stored member order. Present only for static playlists; this is the value the removal endpoint takes. 
  @BuiltValueField(wireName: r'position')
  int? get position;

  @BuiltValueField(wireName: r'item')
  ItemSummary get item;

  PlaylistEntry._();

  factory PlaylistEntry([void updates(PlaylistEntryBuilder b)]) = _$PlaylistEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistEntry> get serializer => _$PlaylistEntrySerializer();
}

class _$PlaylistEntrySerializer implements PrimitiveSerializer<PlaylistEntry> {
  @override
  final Iterable<Type> types = const [PlaylistEntry, _$PlaylistEntry];

  @override
  final String wireName = r'PlaylistEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.position != null) {
      yield r'position';
      yield serializers.serialize(
        object.position,
        specifiedType: const FullType(int),
      );
    }
    yield r'item';
    yield serializers.serialize(
      object.item,
      specifiedType: const FullType(ItemSummary),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaylistEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'position':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.position = valueDes;
          break;
        case r'item':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ItemSummary),
          ) as ItemSummary;
          result.item = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaylistEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistEntryBuilder();
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

