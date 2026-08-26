//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/portable_ref.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_source_update.g.dart';

/// A source binding to store, replacing any previous one whole. Exactly one of `url` (a live source) or `source` with `payload` or `refs` (a matched source, the import request's own fields) must be set. `intervalHours` is required for a live source and must be absent for a matched one. 
///
/// Properties:
/// * [url] - A live source's playlist URL (a YouTube playlist).
/// * [source_] - A matched source's export format, as on the playlist import endpoint: `spotify`, `applemusic`, `ytmusic`, `csv`, `text`, or `portable`. 
/// * [payload] - The export file's text content (text sources).
/// * [refs] - Portable refs (the `portable` source).
/// * [mode] - How a sync reconciles: `append`, `mirror`, or `mirror-trash`. Selecting `mirror-trash` needs the delete right (administrators implicitly), and a matched source takes `append` or `mirror` only. 
/// * [intervalHours] - Hours between scheduled runs (live sources): 1, 3, 6, 12, or 24. Deliberately not a schema enum - the closed set is enforced by the server, where it can grow without a breaking change. 
@BuiltValue()
abstract class PlaylistSourceUpdate implements Built<PlaylistSourceUpdate, PlaylistSourceUpdateBuilder> {
  /// A live source's playlist URL (a YouTube playlist).
  @BuiltValueField(wireName: r'url')
  String? get url;

  /// A matched source's export format, as on the playlist import endpoint: `spotify`, `applemusic`, `ytmusic`, `csv`, `text`, or `portable`. 
  @BuiltValueField(wireName: r'source')
  PlaylistSourceUpdateSource_Enum? get source_;
  // enum source_Enum {  spotify,  applemusic,  ytmusic,  csv,  text,  portable,  };

  /// The export file's text content (text sources).
  @BuiltValueField(wireName: r'payload')
  String? get payload;

  /// Portable refs (the `portable` source).
  @BuiltValueField(wireName: r'refs')
  BuiltList<PortableRef>? get refs;

  /// How a sync reconciles: `append`, `mirror`, or `mirror-trash`. Selecting `mirror-trash` needs the delete right (administrators implicitly), and a matched source takes `append` or `mirror` only. 
  @BuiltValueField(wireName: r'mode')
  PlaylistSourceUpdateModeEnum get mode;
  // enum modeEnum {  append,  mirror,  mirror-trash,  };

  /// Hours between scheduled runs (live sources): 1, 3, 6, 12, or 24. Deliberately not a schema enum - the closed set is enforced by the server, where it can grow without a breaking change. 
  @BuiltValueField(wireName: r'intervalHours')
  int? get intervalHours;

  PlaylistSourceUpdate._();

  factory PlaylistSourceUpdate([void updates(PlaylistSourceUpdateBuilder b)]) = _$PlaylistSourceUpdate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistSourceUpdateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistSourceUpdate> get serializer => _$PlaylistSourceUpdateSerializer();
}

class _$PlaylistSourceUpdateSerializer implements PrimitiveSerializer<PlaylistSourceUpdate> {
  @override
  final Iterable<Type> types = const [PlaylistSourceUpdate, _$PlaylistSourceUpdate];

  @override
  final String wireName = r'PlaylistSourceUpdate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistSourceUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.url != null) {
      yield r'url';
      yield serializers.serialize(
        object.url,
        specifiedType: const FullType(String),
      );
    }
    if (object.source_ != null) {
      yield r'source';
      yield serializers.serialize(
        object.source_,
        specifiedType: const FullType(PlaylistSourceUpdateSource_Enum),
      );
    }
    if (object.payload != null) {
      yield r'payload';
      yield serializers.serialize(
        object.payload,
        specifiedType: const FullType(String),
      );
    }
    if (object.refs != null) {
      yield r'refs';
      yield serializers.serialize(
        object.refs,
        specifiedType: const FullType(BuiltList, [FullType(PortableRef)]),
      );
    }
    yield r'mode';
    yield serializers.serialize(
      object.mode,
      specifiedType: const FullType(PlaylistSourceUpdateModeEnum),
    );
    if (object.intervalHours != null) {
      yield r'intervalHours';
      yield serializers.serialize(
        object.intervalHours,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaylistSourceUpdate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistSourceUpdateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlaylistSourceUpdateSource_Enum),
          ) as PlaylistSourceUpdateSource_Enum;
          result.source_ = valueDes;
          break;
        case r'payload':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.payload = valueDes;
          break;
        case r'refs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PortableRef)]),
          ) as BuiltList<PortableRef>;
          result.refs.replace(valueDes);
          break;
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlaylistSourceUpdateModeEnum),
          ) as PlaylistSourceUpdateModeEnum;
          result.mode = valueDes;
          break;
        case r'intervalHours':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.intervalHours = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaylistSourceUpdate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistSourceUpdateBuilder();
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

class PlaylistSourceUpdateSource_Enum extends EnumClass {

  /// A matched source's export format, as on the playlist import endpoint: `spotify`, `applemusic`, `ytmusic`, `csv`, `text`, or `portable`. 
  @BuiltValueEnumConst(wireName: r'spotify')
  static const PlaylistSourceUpdateSource_Enum spotify = _$playlistSourceUpdateSourceEnum_spotify;
  /// A matched source's export format, as on the playlist import endpoint: `spotify`, `applemusic`, `ytmusic`, `csv`, `text`, or `portable`. 
  @BuiltValueEnumConst(wireName: r'applemusic')
  static const PlaylistSourceUpdateSource_Enum applemusic = _$playlistSourceUpdateSourceEnum_applemusic;
  /// A matched source's export format, as on the playlist import endpoint: `spotify`, `applemusic`, `ytmusic`, `csv`, `text`, or `portable`. 
  @BuiltValueEnumConst(wireName: r'ytmusic')
  static const PlaylistSourceUpdateSource_Enum ytmusic = _$playlistSourceUpdateSourceEnum_ytmusic;
  /// A matched source's export format, as on the playlist import endpoint: `spotify`, `applemusic`, `ytmusic`, `csv`, `text`, or `portable`. 
  @BuiltValueEnumConst(wireName: r'csv')
  static const PlaylistSourceUpdateSource_Enum csv = _$playlistSourceUpdateSourceEnum_csv;
  /// A matched source's export format, as on the playlist import endpoint: `spotify`, `applemusic`, `ytmusic`, `csv`, `text`, or `portable`. 
  @BuiltValueEnumConst(wireName: r'text')
  static const PlaylistSourceUpdateSource_Enum text = _$playlistSourceUpdateSourceEnum_text;
  /// A matched source's export format, as on the playlist import endpoint: `spotify`, `applemusic`, `ytmusic`, `csv`, `text`, or `portable`. 
  @BuiltValueEnumConst(wireName: r'portable')
  static const PlaylistSourceUpdateSource_Enum portable = _$playlistSourceUpdateSourceEnum_portable;
  /// A matched source's export format, as on the playlist import endpoint: `spotify`, `applemusic`, `ytmusic`, `csv`, `text`, or `portable`. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const PlaylistSourceUpdateSource_Enum unknownDefaultOpenApi = _$playlistSourceUpdateSourceEnum_unknownDefaultOpenApi;

  static Serializer<PlaylistSourceUpdateSource_Enum> get serializer => _$playlistSourceUpdateSourceEnumSerializer;

  const PlaylistSourceUpdateSource_Enum._(String name): super(name);

  static BuiltSet<PlaylistSourceUpdateSource_Enum> get values => _$playlistSourceUpdateSourceEnumValues;
  static PlaylistSourceUpdateSource_Enum valueOf(String name) => _$playlistSourceUpdateSourceEnumValueOf(name);
}

class PlaylistSourceUpdateModeEnum extends EnumClass {

  /// How a sync reconciles: `append`, `mirror`, or `mirror-trash`. Selecting `mirror-trash` needs the delete right (administrators implicitly), and a matched source takes `append` or `mirror` only. 
  @BuiltValueEnumConst(wireName: r'append')
  static const PlaylistSourceUpdateModeEnum append = _$playlistSourceUpdateModeEnum_append;
  /// How a sync reconciles: `append`, `mirror`, or `mirror-trash`. Selecting `mirror-trash` needs the delete right (administrators implicitly), and a matched source takes `append` or `mirror` only. 
  @BuiltValueEnumConst(wireName: r'mirror')
  static const PlaylistSourceUpdateModeEnum mirror = _$playlistSourceUpdateModeEnum_mirror;
  /// How a sync reconciles: `append`, `mirror`, or `mirror-trash`. Selecting `mirror-trash` needs the delete right (administrators implicitly), and a matched source takes `append` or `mirror` only. 
  @BuiltValueEnumConst(wireName: r'mirror-trash')
  static const PlaylistSourceUpdateModeEnum mirrorTrash = _$playlistSourceUpdateModeEnum_mirrorTrash;
  /// How a sync reconciles: `append`, `mirror`, or `mirror-trash`. Selecting `mirror-trash` needs the delete right (administrators implicitly), and a matched source takes `append` or `mirror` only. 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const PlaylistSourceUpdateModeEnum unknownDefaultOpenApi = _$playlistSourceUpdateModeEnum_unknownDefaultOpenApi;

  static Serializer<PlaylistSourceUpdateModeEnum> get serializer => _$playlistSourceUpdateModeEnumSerializer;

  const PlaylistSourceUpdateModeEnum._(String name): super(name);

  static BuiltSet<PlaylistSourceUpdateModeEnum> get values => _$playlistSourceUpdateModeEnumValues;
  static PlaylistSourceUpdateModeEnum valueOf(String name) => _$playlistSourceUpdateModeEnumValueOf(name);
}

