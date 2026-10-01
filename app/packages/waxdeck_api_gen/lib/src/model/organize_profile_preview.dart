//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_profile_preview.g.dart';

/// A profile to render samples for; `name` picks what an empty template inherits. 
///
/// Properties:
/// * [name] 
/// * [musicTemplate] 
/// * [audiobookTemplate] 
/// * [podcastTemplate] 
/// * [tagWrite] 
@BuiltValue()
abstract class OrganizeProfilePreview implements Built<OrganizeProfilePreview, OrganizeProfilePreviewBuilder> {
  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'musicTemplate')
  String? get musicTemplate;

  @BuiltValueField(wireName: r'audiobookTemplate')
  String? get audiobookTemplate;

  @BuiltValueField(wireName: r'podcastTemplate')
  String? get podcastTemplate;

  @BuiltValueField(wireName: r'tagWrite')
  bool? get tagWrite;

  OrganizeProfilePreview._();

  factory OrganizeProfilePreview([void updates(OrganizeProfilePreviewBuilder b)]) = _$OrganizeProfilePreview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeProfilePreviewBuilder b) => b
      ..tagWrite = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeProfilePreview> get serializer => _$OrganizeProfilePreviewSerializer();
}

class _$OrganizeProfilePreviewSerializer implements PrimitiveSerializer<OrganizeProfilePreview> {
  @override
  final Iterable<Type> types = const [OrganizeProfilePreview, _$OrganizeProfilePreview];

  @override
  final String wireName = r'OrganizeProfilePreview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeProfilePreview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType(String),
      );
    }
    if (object.musicTemplate != null) {
      yield r'musicTemplate';
      yield serializers.serialize(
        object.musicTemplate,
        specifiedType: const FullType(String),
      );
    }
    if (object.audiobookTemplate != null) {
      yield r'audiobookTemplate';
      yield serializers.serialize(
        object.audiobookTemplate,
        specifiedType: const FullType(String),
      );
    }
    if (object.podcastTemplate != null) {
      yield r'podcastTemplate';
      yield serializers.serialize(
        object.podcastTemplate,
        specifiedType: const FullType(String),
      );
    }
    if (object.tagWrite != null) {
      yield r'tagWrite';
      yield serializers.serialize(
        object.tagWrite,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OrganizeProfilePreview object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeProfilePreviewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.name = valueDes;
          break;
        case r'musicTemplate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.musicTemplate = valueDes;
          break;
        case r'audiobookTemplate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.audiobookTemplate = valueDes;
          break;
        case r'podcastTemplate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.podcastTemplate = valueDes;
          break;
        case r'tagWrite':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(bool),
          ) as bool?;
          if (valueDes == null) continue;
          result.tagWrite = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrganizeProfilePreview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeProfilePreviewBuilder();
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


