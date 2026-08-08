//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'review_identify_request.g.dart';

/// Values to search for in place of what an entry's files claim. Every field is optional and blank fields are dropped; a body with nothing in it clears a stored override. 
///
/// Properties:
/// * [artist] - Stands in for both the artist and the album artist while searching. 
/// * [album] - The album title to search for.
/// * [title] - The track title to search for. Ignored on a unit of several files: a track title belongs to one track, and naming them all the same thing would wreck the pairing that scores a release. Correct a multi-file unit with `artist` and `album`, which are properties of the unit. 
@BuiltValue()
abstract class ReviewIdentifyRequest implements Built<ReviewIdentifyRequest, ReviewIdentifyRequestBuilder> {
  /// Stands in for both the artist and the album artist while searching. 
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// The album title to search for.
  @BuiltValueField(wireName: r'album')
  String? get album;

  /// The track title to search for. Ignored on a unit of several files: a track title belongs to one track, and naming them all the same thing would wreck the pairing that scores a release. Correct a multi-file unit with `artist` and `album`, which are properties of the unit. 
  @BuiltValueField(wireName: r'title')
  String? get title;

  ReviewIdentifyRequest._();

  factory ReviewIdentifyRequest([void updates(ReviewIdentifyRequestBuilder b)]) = _$ReviewIdentifyRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReviewIdentifyRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReviewIdentifyRequest> get serializer => _$ReviewIdentifyRequestSerializer();
}

class _$ReviewIdentifyRequestSerializer implements PrimitiveSerializer<ReviewIdentifyRequest> {
  @override
  final Iterable<Type> types = const [ReviewIdentifyRequest, _$ReviewIdentifyRequest];

  @override
  final String wireName = r'ReviewIdentifyRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReviewIdentifyRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ReviewIdentifyRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReviewIdentifyRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReviewIdentifyRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReviewIdentifyRequestBuilder();
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

