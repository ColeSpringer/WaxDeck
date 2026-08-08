//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'album_detail.g.dart';

/// One album entity's identity and counts.
///
/// Properties:
/// * [pid] - Type-prefixed album PID.
/// * [title] - The release title.
/// * [sortKey] - The collation key the catalog files this album under.
/// * [mbid] - MusicBrainz release ID, when the release is identified.
/// * [year] - Release year.
/// * [releaseGroupPid] - The release group this edition belongs to, when the catalog resolved one. 
/// * [barcode] - The release's barcode (UPC/EAN).
/// * [label] - The issuing label.
/// * [catalogNumber] - The label's catalog number for this release.
/// * [media] - What the release was pressed on, as tagged - \"CD\", \"2xVinyl\", \"Digital Media\". Stored as written: a scan keeps the tag verbatim, so this is a description rather than an enum. 
/// * [country] - Release country, as tagged. A scan stores the tag verbatim, so this can hold a value an edit would refuse (\"US & Europe\") as well as a plain ISO code. 
/// * [itemCount] - Tracks on the release as the catalog holds it. Absent for a caller with restricted library visibility, because the count is not scoped to their grant and a number larger than what they can open would be worse than none. 
/// * [totalDurationMs] - Total running time of those tracks, in milliseconds. Absent alongside `itemCount`, and for its reason. 
@BuiltValue()
abstract class AlbumDetail implements Built<AlbumDetail, AlbumDetailBuilder> {
  /// Type-prefixed album PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// The release title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// The collation key the catalog files this album under.
  @BuiltValueField(wireName: r'sortKey')
  String? get sortKey;

  /// MusicBrainz release ID, when the release is identified.
  @BuiltValueField(wireName: r'mbid')
  String? get mbid;

  /// Release year.
  @BuiltValueField(wireName: r'year')
  int? get year;

  /// The release group this edition belongs to, when the catalog resolved one. 
  @BuiltValueField(wireName: r'releaseGroupPid')
  String? get releaseGroupPid;

  /// The release's barcode (UPC/EAN).
  @BuiltValueField(wireName: r'barcode')
  String? get barcode;

  /// The issuing label.
  @BuiltValueField(wireName: r'label')
  String? get label;

  /// The label's catalog number for this release.
  @BuiltValueField(wireName: r'catalogNumber')
  String? get catalogNumber;

  /// What the release was pressed on, as tagged - \"CD\", \"2xVinyl\", \"Digital Media\". Stored as written: a scan keeps the tag verbatim, so this is a description rather than an enum. 
  @BuiltValueField(wireName: r'media')
  String? get media;

  /// Release country, as tagged. A scan stores the tag verbatim, so this can hold a value an edit would refuse (\"US & Europe\") as well as a plain ISO code. 
  @BuiltValueField(wireName: r'country')
  String? get country;

  /// Tracks on the release as the catalog holds it. Absent for a caller with restricted library visibility, because the count is not scoped to their grant and a number larger than what they can open would be worse than none. 
  @BuiltValueField(wireName: r'itemCount')
  int? get itemCount;

  /// Total running time of those tracks, in milliseconds. Absent alongside `itemCount`, and for its reason. 
  @BuiltValueField(wireName: r'totalDurationMs')
  int? get totalDurationMs;

  AlbumDetail._();

  factory AlbumDetail([void updates(AlbumDetailBuilder b)]) = _$AlbumDetail;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AlbumDetailBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AlbumDetail> get serializer => _$AlbumDetailSerializer();
}

class _$AlbumDetailSerializer implements PrimitiveSerializer<AlbumDetail> {
  @override
  final Iterable<Type> types = const [AlbumDetail, _$AlbumDetail];

  @override
  final String wireName = r'AlbumDetail';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AlbumDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.sortKey != null) {
      yield r'sortKey';
      yield serializers.serialize(
        object.sortKey,
        specifiedType: const FullType(String),
      );
    }
    if (object.mbid != null) {
      yield r'mbid';
      yield serializers.serialize(
        object.mbid,
        specifiedType: const FullType(String),
      );
    }
    if (object.year != null) {
      yield r'year';
      yield serializers.serialize(
        object.year,
        specifiedType: const FullType(int),
      );
    }
    if (object.releaseGroupPid != null) {
      yield r'releaseGroupPid';
      yield serializers.serialize(
        object.releaseGroupPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.barcode != null) {
      yield r'barcode';
      yield serializers.serialize(
        object.barcode,
        specifiedType: const FullType(String),
      );
    }
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType(String),
      );
    }
    if (object.catalogNumber != null) {
      yield r'catalogNumber';
      yield serializers.serialize(
        object.catalogNumber,
        specifiedType: const FullType(String),
      );
    }
    if (object.media != null) {
      yield r'media';
      yield serializers.serialize(
        object.media,
        specifiedType: const FullType(String),
      );
    }
    if (object.country != null) {
      yield r'country';
      yield serializers.serialize(
        object.country,
        specifiedType: const FullType(String),
      );
    }
    if (object.itemCount != null) {
      yield r'itemCount';
      yield serializers.serialize(
        object.itemCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.totalDurationMs != null) {
      yield r'totalDurationMs';
      yield serializers.serialize(
        object.totalDurationMs,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AlbumDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AlbumDetailBuilder result,
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
        case r'sortKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sortKey = valueDes;
          break;
        case r'mbid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mbid = valueDes;
          break;
        case r'year':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.year = valueDes;
          break;
        case r'releaseGroupPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.releaseGroupPid = valueDes;
          break;
        case r'barcode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.barcode = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.label = valueDes;
          break;
        case r'catalogNumber':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.catalogNumber = valueDes;
          break;
        case r'media':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.media = valueDes;
          break;
        case r'country':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.country = valueDes;
          break;
        case r'itemCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.itemCount = valueDes;
          break;
        case r'totalDurationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalDurationMs = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AlbumDetail deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AlbumDetailBuilder();
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

