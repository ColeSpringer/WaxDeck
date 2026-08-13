//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'portable_ref.g.dart';

/// A catalog-independent identity descriptor for one playable item, carrying the progressively fuzzier anchors the resolve ladder walks. Produced by the portable export; consumed by the `portable` import source. 
///
/// Properties:
/// * [kind] - What the ref describes.
/// * [essence] - Exact-rip audio-essence hash.
/// * [fingerprint] - Packed acoustic fingerprint, base64.
/// * [fingerprintAlgo] - Fingerprint algorithm: 1 pure-Go, 100 Chromaprint.
/// * [mbid] - Recording MBID (track) or release MBID (book).
/// * [asin] - Audiobook ASIN.
/// * [isbn] - Audiobook ISBN.
/// * [isrc] - Recording ISRC. Import upgrades it to a recording MBID through MusicBrainz when the server has internet. 
/// * [artist] - Track artist, or book author.
/// * [title] - Display title.
/// * [album] - Track album, or book series.
/// * [durationMs] - Duration in milliseconds.
@BuiltValue()
abstract class PortableRef implements Built<PortableRef, PortableRefBuilder> {
  /// What the ref describes.
  @BuiltValueField(wireName: r'kind')
  PortableRefKindEnum get kind;
  // enum kindEnum {  track,  book,  episode,  };

  /// Exact-rip audio-essence hash.
  @BuiltValueField(wireName: r'essence')
  String? get essence;

  /// Packed acoustic fingerprint, base64.
  @BuiltValueField(wireName: r'fingerprint')
  String? get fingerprint;

  /// Fingerprint algorithm: 1 pure-Go, 100 Chromaprint.
  @BuiltValueField(wireName: r'fingerprintAlgo')
  int? get fingerprintAlgo;

  /// Recording MBID (track) or release MBID (book).
  @BuiltValueField(wireName: r'mbid')
  String? get mbid;

  /// Audiobook ASIN.
  @BuiltValueField(wireName: r'asin')
  String? get asin;

  /// Audiobook ISBN.
  @BuiltValueField(wireName: r'isbn')
  String? get isbn;

  /// Recording ISRC. Import upgrades it to a recording MBID through MusicBrainz when the server has internet. 
  @BuiltValueField(wireName: r'isrc')
  String? get isrc;

  /// Track artist, or book author.
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// Display title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Track album, or book series.
  @BuiltValueField(wireName: r'album')
  String? get album;

  /// Duration in milliseconds.
  @BuiltValueField(wireName: r'durationMs')
  int? get durationMs;

  PortableRef._();

  factory PortableRef([void updates(PortableRefBuilder b)]) = _$PortableRef;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PortableRefBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PortableRef> get serializer => _$PortableRefSerializer();
}

class _$PortableRefSerializer implements PrimitiveSerializer<PortableRef> {
  @override
  final Iterable<Type> types = const [PortableRef, _$PortableRef];

  @override
  final String wireName = r'PortableRef';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PortableRef object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(PortableRefKindEnum),
    );
    if (object.essence != null) {
      yield r'essence';
      yield serializers.serialize(
        object.essence,
        specifiedType: const FullType(String),
      );
    }
    if (object.fingerprint != null) {
      yield r'fingerprint';
      yield serializers.serialize(
        object.fingerprint,
        specifiedType: const FullType(String),
      );
    }
    if (object.fingerprintAlgo != null) {
      yield r'fingerprintAlgo';
      yield serializers.serialize(
        object.fingerprintAlgo,
        specifiedType: const FullType(int),
      );
    }
    if (object.mbid != null) {
      yield r'mbid';
      yield serializers.serialize(
        object.mbid,
        specifiedType: const FullType(String),
      );
    }
    if (object.asin != null) {
      yield r'asin';
      yield serializers.serialize(
        object.asin,
        specifiedType: const FullType(String),
      );
    }
    if (object.isbn != null) {
      yield r'isbn';
      yield serializers.serialize(
        object.isbn,
        specifiedType: const FullType(String),
      );
    }
    if (object.isrc != null) {
      yield r'isrc';
      yield serializers.serialize(
        object.isrc,
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
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.album != null) {
      yield r'album';
      yield serializers.serialize(
        object.album,
        specifiedType: const FullType(String),
      );
    }
    if (object.durationMs != null) {
      yield r'durationMs';
      yield serializers.serialize(
        object.durationMs,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PortableRef object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PortableRefBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PortableRefKindEnum),
          ) as PortableRefKindEnum;
          result.kind = valueDes;
          break;
        case r'essence':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.essence = valueDes;
          break;
        case r'fingerprint':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fingerprint = valueDes;
          break;
        case r'fingerprintAlgo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.fingerprintAlgo = valueDes;
          break;
        case r'mbid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mbid = valueDes;
          break;
        case r'asin':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.asin = valueDes;
          break;
        case r'isbn':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.isbn = valueDes;
          break;
        case r'isrc':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.isrc = valueDes;
          break;
        case r'artist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artist = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'album':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.album = valueDes;
          break;
        case r'durationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMs = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PortableRef deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PortableRefBuilder();
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

class PortableRefKindEnum extends EnumClass {

  /// What the ref describes.
  @BuiltValueEnumConst(wireName: r'track')
  static const PortableRefKindEnum track = _$portableRefKindEnum_track;
  /// What the ref describes.
  @BuiltValueEnumConst(wireName: r'book')
  static const PortableRefKindEnum book = _$portableRefKindEnum_book;
  /// What the ref describes.
  @BuiltValueEnumConst(wireName: r'episode')
  static const PortableRefKindEnum episode = _$portableRefKindEnum_episode;
  /// What the ref describes.
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const PortableRefKindEnum unknownDefaultOpenApi = _$portableRefKindEnum_unknownDefaultOpenApi;

  static Serializer<PortableRefKindEnum> get serializer => _$portableRefKindEnumSerializer;

  const PortableRefKindEnum._(String name): super(name);

  static BuiltSet<PortableRefKindEnum> get values => _$portableRefKindEnumValues;
  static PortableRefKindEnum valueOf(String name) => _$portableRefKindEnumValueOf(name);
}

