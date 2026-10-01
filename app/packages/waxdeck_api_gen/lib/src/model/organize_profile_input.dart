//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_profile_input.g.dart';

/// A profile to save. An empty or absent template inherits the built-in of the same name, or the native layout. 
///
/// Properties:
/// * [musicTemplate] 
/// * [audiobookTemplate] 
/// * [podcastTemplate] 
/// * [tagWrite] 
@BuiltValue()
abstract class OrganizeProfileInput implements Built<OrganizeProfileInput, OrganizeProfileInputBuilder> {
  @BuiltValueField(wireName: r'musicTemplate')
  String? get musicTemplate;

  @BuiltValueField(wireName: r'audiobookTemplate')
  String? get audiobookTemplate;

  @BuiltValueField(wireName: r'podcastTemplate')
  String? get podcastTemplate;

  @BuiltValueField(wireName: r'tagWrite')
  bool? get tagWrite;

  OrganizeProfileInput._();

  factory OrganizeProfileInput([void updates(OrganizeProfileInputBuilder b)]) = _$OrganizeProfileInput;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeProfileInputBuilder b) => b
      ..tagWrite = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeProfileInput> get serializer => _$OrganizeProfileInputSerializer();
}

class _$OrganizeProfileInputSerializer implements PrimitiveSerializer<OrganizeProfileInput> {
  @override
  final Iterable<Type> types = const [OrganizeProfileInput, _$OrganizeProfileInput];

  @override
  final String wireName = r'OrganizeProfileInput';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeProfileInput object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    OrganizeProfileInput object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeProfileInputBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
  OrganizeProfileInput deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeProfileInputBuilder();
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


