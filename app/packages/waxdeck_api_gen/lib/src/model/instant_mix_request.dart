//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'instant_mix_request.g.dart';

/// A mix seed. Exactly one of `seedPid` and `genre` must be set. 
///
/// Properties:
/// * [seedPid] - Seed track (`tr-`), artist (`ar-`), or album (`al-`) pid. An artist or album seed anchors the mix on that entity's tracks (resolved by entity identity, so the mix follows the catalog's grouping rather than a display-string match). 
/// * [genre] - Seed genre name, matched case-insensitively.
/// * [adventurousness] - How far the mix wanders from the seed. 0 hugs the seed's closest sonic neighbors; 1 wanders far. On the metadata fallback this loosens the genre bound instead. 
/// * [size] - Requested mix length in tracks.
/// * [excludePids] - Tracks to leave out (already played in this radio session). The seed is always excluded. 
@BuiltValue()
abstract class InstantMixRequest implements Built<InstantMixRequest, InstantMixRequestBuilder> {
  /// Seed track (`tr-`), artist (`ar-`), or album (`al-`) pid. An artist or album seed anchors the mix on that entity's tracks (resolved by entity identity, so the mix follows the catalog's grouping rather than a display-string match). 
  @BuiltValueField(wireName: r'seedPid')
  String? get seedPid;

  /// Seed genre name, matched case-insensitively.
  @BuiltValueField(wireName: r'genre')
  String? get genre;

  /// How far the mix wanders from the seed. 0 hugs the seed's closest sonic neighbors; 1 wanders far. On the metadata fallback this loosens the genre bound instead. 
  @BuiltValueField(wireName: r'adventurousness')
  num? get adventurousness;

  /// Requested mix length in tracks.
  @BuiltValueField(wireName: r'size')
  int? get size;

  /// Tracks to leave out (already played in this radio session). The seed is always excluded. 
  @BuiltValueField(wireName: r'excludePids')
  BuiltList<String>? get excludePids;

  InstantMixRequest._();

  factory InstantMixRequest([void updates(InstantMixRequestBuilder b)]) = _$InstantMixRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InstantMixRequestBuilder b) => b
      ..adventurousness = 0.4
      ..size = 50;

  @BuiltValueSerializer(custom: true)
  static Serializer<InstantMixRequest> get serializer => _$InstantMixRequestSerializer();
}

class _$InstantMixRequestSerializer implements PrimitiveSerializer<InstantMixRequest> {
  @override
  final Iterable<Type> types = const [InstantMixRequest, _$InstantMixRequest];

  @override
  final String wireName = r'InstantMixRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InstantMixRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.seedPid != null) {
      yield r'seedPid';
      yield serializers.serialize(
        object.seedPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.genre != null) {
      yield r'genre';
      yield serializers.serialize(
        object.genre,
        specifiedType: const FullType(String),
      );
    }
    if (object.adventurousness != null) {
      yield r'adventurousness';
      yield serializers.serialize(
        object.adventurousness,
        specifiedType: const FullType(num),
      );
    }
    if (object.size != null) {
      yield r'size';
      yield serializers.serialize(
        object.size,
        specifiedType: const FullType(int),
      );
    }
    if (object.excludePids != null) {
      yield r'excludePids';
      yield serializers.serialize(
        object.excludePids,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InstantMixRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InstantMixRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'seedPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.seedPid = valueDes;
          break;
        case r'genre':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.genre = valueDes;
          break;
        case r'adventurousness':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.adventurousness = valueDes;
          break;
        case r'size':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.size = valueDes;
          break;
        case r'excludePids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.excludePids.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InstantMixRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InstantMixRequestBuilder();
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

