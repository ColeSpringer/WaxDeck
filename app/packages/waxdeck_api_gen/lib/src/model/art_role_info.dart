//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/art_role.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'art_role_info.g.dart';

/// One artwork slot an entity holds at its own level, with where its image came from and whether it is pinned.  A slot that reports `locked: true` and no `format` is a lock with nothing behind it: the cover was cleared and pinned cleared, which means \"do not refill this\" rather than \"this has no cover yet\". It is the one artwork state that was previously invisible, and it is why an entity can list a role at all while holding no image. Only `front` can be locked; the auxiliary slots have no producer to guard against, so they always report false. 
///
/// Properties:
/// * [role] 
/// * [format] - The format token the catalog stored for this image, lowercase (`jpeg`, `png`, `webp`, `gif`, `bmp`, `tiff`, and the exotics a caller declared or the bytes announced). An open set, not a fixed list: it widens whenever a decoder or a sniffer is added, so treat an unfamiliar token as a format this client does not draw rather than as an error. Absent when the slot holds no image, which happens only on a locked-and-cleared `front`. 
/// * [width] - Pixel width, 0 when nothing could measure the image. A cover the server cannot decode may still report real dimensions when its tag declared them, so 0 means \"unmeasured\" rather than \"undecodable\" and is not a count to divide by. 
/// * [height] - Pixel height, 0 when nothing could measure the image. See `width`. 
/// * [source_] - Where this slot's image came from, in `ArtSource`'s vocabulary (`tag`, `sidecar`, `user`, `enrichment`, `feed`, `generated`). A string, not a closed enum. 
/// * [provider] - The provider that supplied an `enrichment` cover.
/// * [sourceUrl] - Where a fetched cover's bytes came from.
/// * [updatedAt] - When this slot was last written.
/// * [locked] - Whether the entity's front cover is pinned against enrichment and scan re-derives. False on every non-front role. 
@BuiltValue()
abstract class ArtRoleInfo implements Built<ArtRoleInfo, ArtRoleInfoBuilder> {
  @BuiltValueField(wireName: r'role')
  ArtRole get role;
  // enum roleEnum {  front,  back,  disc,  booklet,  background,  };

  /// The format token the catalog stored for this image, lowercase (`jpeg`, `png`, `webp`, `gif`, `bmp`, `tiff`, and the exotics a caller declared or the bytes announced). An open set, not a fixed list: it widens whenever a decoder or a sniffer is added, so treat an unfamiliar token as a format this client does not draw rather than as an error. Absent when the slot holds no image, which happens only on a locked-and-cleared `front`. 
  @BuiltValueField(wireName: r'format')
  String? get format;

  /// Pixel width, 0 when nothing could measure the image. A cover the server cannot decode may still report real dimensions when its tag declared them, so 0 means \"unmeasured\" rather than \"undecodable\" and is not a count to divide by. 
  @BuiltValueField(wireName: r'width')
  int? get width;

  /// Pixel height, 0 when nothing could measure the image. See `width`. 
  @BuiltValueField(wireName: r'height')
  int? get height;

  /// Where this slot's image came from, in `ArtSource`'s vocabulary (`tag`, `sidecar`, `user`, `enrichment`, `feed`, `generated`). A string, not a closed enum. 
  @BuiltValueField(wireName: r'source')
  String? get source_;

  /// The provider that supplied an `enrichment` cover.
  @BuiltValueField(wireName: r'provider')
  String? get provider;

  /// Where a fetched cover's bytes came from.
  @BuiltValueField(wireName: r'sourceUrl')
  String? get sourceUrl;

  /// When this slot was last written.
  @BuiltValueField(wireName: r'updatedAt')
  DateTime? get updatedAt;

  /// Whether the entity's front cover is pinned against enrichment and scan re-derives. False on every non-front role. 
  @BuiltValueField(wireName: r'locked')
  bool? get locked;

  ArtRoleInfo._();

  factory ArtRoleInfo([void updates(ArtRoleInfoBuilder b)]) = _$ArtRoleInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ArtRoleInfoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ArtRoleInfo> get serializer => _$ArtRoleInfoSerializer();
}

class _$ArtRoleInfoSerializer implements PrimitiveSerializer<ArtRoleInfo> {
  @override
  final Iterable<Type> types = const [ArtRoleInfo, _$ArtRoleInfo];

  @override
  final String wireName = r'ArtRoleInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ArtRoleInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(ArtRole),
    );
    if (object.format != null) {
      yield r'format';
      yield serializers.serialize(
        object.format,
        specifiedType: const FullType(String),
      );
    }
    if (object.width != null) {
      yield r'width';
      yield serializers.serialize(
        object.width,
        specifiedType: const FullType(int),
      );
    }
    if (object.height != null) {
      yield r'height';
      yield serializers.serialize(
        object.height,
        specifiedType: const FullType(int),
      );
    }
    if (object.source_ != null) {
      yield r'source';
      yield serializers.serialize(
        object.source_,
        specifiedType: const FullType(String),
      );
    }
    if (object.provider != null) {
      yield r'provider';
      yield serializers.serialize(
        object.provider,
        specifiedType: const FullType(String),
      );
    }
    if (object.sourceUrl != null) {
      yield r'sourceUrl';
      yield serializers.serialize(
        object.sourceUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.updatedAt != null) {
      yield r'updatedAt';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.locked != null) {
      yield r'locked';
      yield serializers.serialize(
        object.locked,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ArtRoleInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ArtRoleInfoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ArtRole),
          ) as ArtRole;
          result.role = valueDes;
          break;
        case r'format':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.format = valueDes;
          break;
        case r'width':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.width = valueDes;
          break;
        case r'height':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.height = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.source_ = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.provider = valueDes;
          break;
        case r'sourceUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceUrl = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        case r'locked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.locked = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ArtRoleInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ArtRoleInfoBuilder();
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

