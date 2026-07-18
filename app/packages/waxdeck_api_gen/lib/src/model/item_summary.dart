//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item_summary.g.dart';

/// Compact item representation used by list endpoints and client-side library mirrors (~summary row). 
///
/// Properties:
/// * [pid] - Type-prefixed ULID.
/// * [mediaType] 
/// * [title] - Display title.
/// * [artist] - Primary display artist / author / show name.
/// * [album] - Album / series / podcast title, when applicable.
/// * [durationMs] - Duration in milliseconds.
/// * [artUrl] - Origin-relative URL of the item's artwork endpoint. Always populated; the endpoint itself returns 404 for items with no artwork, so clients keep a placeholder ready. 
@BuiltValue(instantiable: false)
abstract class ItemSummary  {
  /// Type-prefixed ULID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  @BuiltValueField(wireName: r'mediaType')
  MediaType get mediaType;
  // enum mediaTypeEnum {  music,  podcast,  audiobook,  };

  /// Display title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Primary display artist / author / show name.
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// Album / series / podcast title, when applicable.
  @BuiltValueField(wireName: r'album')
  String? get album;

  /// Duration in milliseconds.
  @BuiltValueField(wireName: r'durationMs')
  int get durationMs;

  /// Origin-relative URL of the item's artwork endpoint. Always populated; the endpoint itself returns 404 for items with no artwork, so clients keep a placeholder ready. 
  @BuiltValueField(wireName: r'artUrl')
  String? get artUrl;

  @BuiltValueSerializer(custom: true)
  static Serializer<ItemSummary> get serializer => _$ItemSummarySerializer();
}

class _$ItemSummarySerializer implements PrimitiveSerializer<ItemSummary> {
  @override
  final Iterable<Type> types = const [ItemSummary];

  @override
  final String wireName = r'ItemSummary';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ItemSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'mediaType';
    yield serializers.serialize(
      object.mediaType,
      specifiedType: const FullType(MediaType),
    );
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    if (object.album != null) {
      yield r'album';
      yield serializers.serialize(
        object.album,
        specifiedType: const FullType(String),
      );
    }
    yield r'durationMs';
    yield serializers.serialize(
      object.durationMs,
      specifiedType: const FullType(int),
    );
    if (object.artUrl != null) {
      yield r'artUrl';
      yield serializers.serialize(
        object.artUrl,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ItemSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  ItemSummary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($ItemSummary)) as $ItemSummary;
  }
}

/// a concrete implementation of [ItemSummary], since [ItemSummary] is not instantiable
@BuiltValue(instantiable: true)
abstract class $ItemSummary implements ItemSummary, Built<$ItemSummary, $ItemSummaryBuilder> {
  $ItemSummary._();

  factory $ItemSummary([void Function($ItemSummaryBuilder)? updates]) = _$$ItemSummary;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($ItemSummaryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$ItemSummary> get serializer => _$$ItemSummarySerializer();
}

class _$$ItemSummarySerializer implements PrimitiveSerializer<$ItemSummary> {
  @override
  final Iterable<Type> types = const [$ItemSummary, _$$ItemSummary];

  @override
  final String wireName = r'$ItemSummary';

  @override
  Object serialize(
    Serializers serializers,
    $ItemSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(ItemSummary))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ItemSummaryBuilder result,
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
        case r'mediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaType),
          ) as MediaType;
          result.mediaType = valueDes;
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
        case r'artUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  $ItemSummary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $ItemSummaryBuilder();
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

