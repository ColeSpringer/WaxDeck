//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/portable_ref.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'playlist_import_request.g.dart';

/// A playlist to import. `payload` carries the export text for the text sources; `refs` carries portable refs for the `portable` source. Exactly the field matching `source` must be set. 
///
/// Properties:
/// * [source_] - The export format: `spotify` (Exportify CSV), `applemusic` (tab-separated export), `ytmusic` (Google Takeout CSV), `csv` (generic with artist, title, album, duration columns), `text` (one `Artist - Title` per line), or `portable` (another WaxDeck's portable export). 
/// * [name] - Name for the created playlist. Defaults to a name found in the export, or `Imported playlist`. 
/// * [payload] - The export file's text content (text sources).
/// * [refs] - Portable refs (the `portable` source).
@BuiltValue()
abstract class PlaylistImportRequest implements Built<PlaylistImportRequest, PlaylistImportRequestBuilder> {
  /// The export format: `spotify` (Exportify CSV), `applemusic` (tab-separated export), `ytmusic` (Google Takeout CSV), `csv` (generic with artist, title, album, duration columns), `text` (one `Artist - Title` per line), or `portable` (another WaxDeck's portable export). 
  @BuiltValueField(wireName: r'source')
  PlaylistImportRequestSource_Enum get source_;
  // enum source_Enum {  spotify,  applemusic,  ytmusic,  csv,  text,  portable,  };

  /// Name for the created playlist. Defaults to a name found in the export, or `Imported playlist`. 
  @BuiltValueField(wireName: r'name')
  String? get name;

  /// The export file's text content (text sources).
  @BuiltValueField(wireName: r'payload')
  String? get payload;

  /// Portable refs (the `portable` source).
  @BuiltValueField(wireName: r'refs')
  BuiltList<PortableRef>? get refs;

  PlaylistImportRequest._();

  factory PlaylistImportRequest([void updates(PlaylistImportRequestBuilder b)]) = _$PlaylistImportRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaylistImportRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaylistImportRequest> get serializer => _$PlaylistImportRequestSerializer();
}

class _$PlaylistImportRequestSerializer implements PrimitiveSerializer<PlaylistImportRequest> {
  @override
  final Iterable<Type> types = const [PlaylistImportRequest, _$PlaylistImportRequest];

  @override
  final String wireName = r'PlaylistImportRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaylistImportRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(PlaylistImportRequestSource_Enum),
    );
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType(String),
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
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaylistImportRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaylistImportRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlaylistImportRequestSource_Enum),
          ) as PlaylistImportRequestSource_Enum;
          result.source_ = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaylistImportRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaylistImportRequestBuilder();
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

class PlaylistImportRequestSource_Enum extends EnumClass {

  /// The export format: `spotify` (Exportify CSV), `applemusic` (tab-separated export), `ytmusic` (Google Takeout CSV), `csv` (generic with artist, title, album, duration columns), `text` (one `Artist - Title` per line), or `portable` (another WaxDeck's portable export). 
  @BuiltValueEnumConst(wireName: r'spotify')
  static const PlaylistImportRequestSource_Enum spotify = _$playlistImportRequestSourceEnum_spotify;
  /// The export format: `spotify` (Exportify CSV), `applemusic` (tab-separated export), `ytmusic` (Google Takeout CSV), `csv` (generic with artist, title, album, duration columns), `text` (one `Artist - Title` per line), or `portable` (another WaxDeck's portable export). 
  @BuiltValueEnumConst(wireName: r'applemusic')
  static const PlaylistImportRequestSource_Enum applemusic = _$playlistImportRequestSourceEnum_applemusic;
  /// The export format: `spotify` (Exportify CSV), `applemusic` (tab-separated export), `ytmusic` (Google Takeout CSV), `csv` (generic with artist, title, album, duration columns), `text` (one `Artist - Title` per line), or `portable` (another WaxDeck's portable export). 
  @BuiltValueEnumConst(wireName: r'ytmusic')
  static const PlaylistImportRequestSource_Enum ytmusic = _$playlistImportRequestSourceEnum_ytmusic;
  /// The export format: `spotify` (Exportify CSV), `applemusic` (tab-separated export), `ytmusic` (Google Takeout CSV), `csv` (generic with artist, title, album, duration columns), `text` (one `Artist - Title` per line), or `portable` (another WaxDeck's portable export). 
  @BuiltValueEnumConst(wireName: r'csv')
  static const PlaylistImportRequestSource_Enum csv = _$playlistImportRequestSourceEnum_csv;
  /// The export format: `spotify` (Exportify CSV), `applemusic` (tab-separated export), `ytmusic` (Google Takeout CSV), `csv` (generic with artist, title, album, duration columns), `text` (one `Artist - Title` per line), or `portable` (another WaxDeck's portable export). 
  @BuiltValueEnumConst(wireName: r'text')
  static const PlaylistImportRequestSource_Enum text = _$playlistImportRequestSourceEnum_text;
  /// The export format: `spotify` (Exportify CSV), `applemusic` (tab-separated export), `ytmusic` (Google Takeout CSV), `csv` (generic with artist, title, album, duration columns), `text` (one `Artist - Title` per line), or `portable` (another WaxDeck's portable export). 
  @BuiltValueEnumConst(wireName: r'portable')
  static const PlaylistImportRequestSource_Enum portable = _$playlistImportRequestSourceEnum_portable;
  /// The export format: `spotify` (Exportify CSV), `applemusic` (tab-separated export), `ytmusic` (Google Takeout CSV), `csv` (generic with artist, title, album, duration columns), `text` (one `Artist - Title` per line), or `portable` (another WaxDeck's portable export). 
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const PlaylistImportRequestSource_Enum unknownDefaultOpenApi = _$playlistImportRequestSourceEnum_unknownDefaultOpenApi;

  static Serializer<PlaylistImportRequestSource_Enum> get serializer => _$playlistImportRequestSourceEnumSerializer;

  const PlaylistImportRequestSource_Enum._(String name): super(name);

  static BuiltSet<PlaylistImportRequestSource_Enum> get values => _$playlistImportRequestSourceEnumValues;
  static PlaylistImportRequestSource_Enum valueOf(String name) => _$playlistImportRequestSourceEnumValueOf(name);
}

