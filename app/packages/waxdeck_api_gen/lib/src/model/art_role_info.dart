//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/art_role.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'art_role_info.g.dart';

/// One artwork slot an entity holds at its own level.
///
/// Properties:
/// * [role] 
/// * [format] - The stored image format (`jpeg`, `png`, `webp`, `gif`).
/// * [width] - Pixel width, 0 when the image was not decodable.
/// * [height] - Pixel height, 0 when the image was not decodable.
@BuiltValue()
abstract class ArtRoleInfo implements Built<ArtRoleInfo, ArtRoleInfoBuilder> {
  @BuiltValueField(wireName: r'role')
  ArtRole get role;
  // enum roleEnum {  front,  back,  disc,  booklet,  background,  };

  /// The stored image format (`jpeg`, `png`, `webp`, `gif`).
  @BuiltValueField(wireName: r'format')
  String? get format;

  /// Pixel width, 0 when the image was not decodable.
  @BuiltValueField(wireName: r'width')
  int? get width;

  /// Pixel height, 0 when the image was not decodable.
  @BuiltValueField(wireName: r'height')
  int? get height;

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

