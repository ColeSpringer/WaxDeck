//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'listen_log_entry.g.dart';

/// One recorded listen session.
///
/// Properties:
/// * [pid] - The item that was played.
/// * [title] - The item's display title at read time. Absent when the item has left the catalog entirely. 
/// * [artist] - The item's display artist, author, or show.
/// * [mediaType] 
/// * [startedAt] - When playback started.
/// * [msPlayed] - Milliseconds actually heard.
/// * [skippedMs] - Milliseconds saved by silence trimming and speed-up, when the client reported them. 
/// * [finished] - Whether playback reached the end of the item.
/// * [client] - The reporting client label.
/// * [source_] - `live` playback or a backdated `import`.
@BuiltValue()
abstract class ListenLogEntry implements Built<ListenLogEntry, ListenLogEntryBuilder> {
  /// The item that was played.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// The item's display title at read time. Absent when the item has left the catalog entirely. 
  @BuiltValueField(wireName: r'title')
  String? get title;

  /// The item's display artist, author, or show.
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  /// When playback started.
  @BuiltValueField(wireName: r'startedAt')
  DateTime get startedAt;

  /// Milliseconds actually heard.
  @BuiltValueField(wireName: r'msPlayed')
  int get msPlayed;

  /// Milliseconds saved by silence trimming and speed-up, when the client reported them. 
  @BuiltValueField(wireName: r'skippedMs')
  int? get skippedMs;

  /// Whether playback reached the end of the item.
  @BuiltValueField(wireName: r'finished')
  bool get finished;

  /// The reporting client label.
  @BuiltValueField(wireName: r'client')
  String get client;

  /// `live` playback or a backdated `import`.
  @BuiltValueField(wireName: r'source')
  ListenLogEntrySource_Enum get source_;
  // enum source_Enum {  live,  import,  };

  ListenLogEntry._();

  factory ListenLogEntry([void updates(ListenLogEntryBuilder b)]) = _$ListenLogEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListenLogEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListenLogEntry> get serializer => _$ListenLogEntrySerializer();
}

class _$ListenLogEntrySerializer implements PrimitiveSerializer<ListenLogEntry> {
  @override
  final Iterable<Type> types = const [ListenLogEntry, _$ListenLogEntry];

  @override
  final String wireName = r'ListenLogEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListenLogEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType(String),
      );
    }
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    yield r'mediaType';
    yield serializers.serialize(
      object.mediaType,
      specifiedType: const FullType(MediaType),
    );
    yield r'startedAt';
    yield serializers.serialize(
      object.startedAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'msPlayed';
    yield serializers.serialize(
      object.msPlayed,
      specifiedType: const FullType(int),
    );
    if (object.skippedMs != null) {
      yield r'skippedMs';
      yield serializers.serialize(
        object.skippedMs,
        specifiedType: const FullType(int),
      );
    }
    yield r'finished';
    yield serializers.serialize(
      object.finished,
      specifiedType: const FullType(bool),
    );
    yield r'client';
    yield serializers.serialize(
      object.client,
      specifiedType: const FullType(String),
    );
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(ListenLogEntrySource_Enum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ListenLogEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListenLogEntryBuilder result,
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
        case r'mediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaType),
          ) as MediaType;
          result.mediaType = valueDes;
          break;
        case r'startedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startedAt = valueDes;
          break;
        case r'msPlayed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.msPlayed = valueDes;
          break;
        case r'skippedMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.skippedMs = valueDes;
          break;
        case r'finished':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.finished = valueDes;
          break;
        case r'client':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.client = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ListenLogEntrySource_Enum),
          ) as ListenLogEntrySource_Enum;
          result.source_ = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ListenLogEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListenLogEntryBuilder();
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

class ListenLogEntrySource_Enum extends EnumClass {

  /// `live` playback or a backdated `import`.
  @BuiltValueEnumConst(wireName: r'live')
  static const ListenLogEntrySource_Enum live = _$listenLogEntrySourceEnum_live;
  /// `live` playback or a backdated `import`.
  @BuiltValueEnumConst(wireName: r'import')
  static const ListenLogEntrySource_Enum import_ = _$listenLogEntrySourceEnum_import_;
  /// `live` playback or a backdated `import`.
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const ListenLogEntrySource_Enum unknownDefaultOpenApi = _$listenLogEntrySourceEnum_unknownDefaultOpenApi;

  static Serializer<ListenLogEntrySource_Enum> get serializer => _$listenLogEntrySourceEnumSerializer;

  const ListenLogEntrySource_Enum._(String name): super(name);

  static BuiltSet<ListenLogEntrySource_Enum> get values => _$listenLogEntrySourceEnumValues;
  static ListenLogEntrySource_Enum valueOf(String name) => _$listenLogEntrySourceEnumValueOf(name);
}

