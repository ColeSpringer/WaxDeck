//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_templates.g.dart';

/// The templates a saved profile sets itself; an empty one inherits. Absent for a built-in nothing overrides. 
///
/// Properties:
/// * [musicTemplate] 
/// * [audiobookTemplate] 
/// * [podcastTemplate] 
@BuiltValue()
abstract class OrganizeTemplates implements Built<OrganizeTemplates, OrganizeTemplatesBuilder> {
  @BuiltValueField(wireName: r'musicTemplate')
  String get musicTemplate;

  @BuiltValueField(wireName: r'audiobookTemplate')
  String get audiobookTemplate;

  @BuiltValueField(wireName: r'podcastTemplate')
  String get podcastTemplate;

  OrganizeTemplates._();

  factory OrganizeTemplates([void updates(OrganizeTemplatesBuilder b)]) = _$OrganizeTemplates;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeTemplatesBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeTemplates> get serializer => _$OrganizeTemplatesSerializer();
}

class _$OrganizeTemplatesSerializer implements PrimitiveSerializer<OrganizeTemplates> {
  @override
  final Iterable<Type> types = const [OrganizeTemplates, _$OrganizeTemplates];

  @override
  final String wireName = r'OrganizeTemplates';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeTemplates object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'musicTemplate';
    yield serializers.serialize(
      object.musicTemplate,
      specifiedType: const FullType(String),
    );
    yield r'audiobookTemplate';
    yield serializers.serialize(
      object.audiobookTemplate,
      specifiedType: const FullType(String),
    );
    yield r'podcastTemplate';
    yield serializers.serialize(
      object.podcastTemplate,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OrganizeTemplates object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeTemplatesBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'musicTemplate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.musicTemplate = valueDes;
          break;
        case r'audiobookTemplate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.audiobookTemplate = valueDes;
          break;
        case r'podcastTemplate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.podcastTemplate = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrganizeTemplates deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeTemplatesBuilder();
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


