//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/organize_templates.dart';
import 'package:waxdeck_api_gen/src/model/organize_sample.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_profile.g.dart';

/// One organize profile, its templates after inheritance.
///
/// Properties:
/// * [name] - The profile name organize requests reference.
/// * [musicTemplate] - Path template for music.
/// * [audiobookTemplate] - Path template for audiobooks.
/// * [podcastTemplate] - Path template for podcast files.
/// * [tagWrite] - Whether organizing also writes tags.
/// * [builtIn] - A built-in no saved profile overrides; it cannot be deleted.
/// * [sample] 
/// * [saved] 
@BuiltValue()
abstract class OrganizeProfile implements Built<OrganizeProfile, OrganizeProfileBuilder> {
  /// The profile name organize requests reference.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Path template for music.
  @BuiltValueField(wireName: r'musicTemplate')
  String get musicTemplate;

  /// Path template for audiobooks.
  @BuiltValueField(wireName: r'audiobookTemplate')
  String get audiobookTemplate;

  /// Path template for podcast files.
  @BuiltValueField(wireName: r'podcastTemplate')
  String get podcastTemplate;

  /// Whether organizing also writes tags.
  @BuiltValueField(wireName: r'tagWrite')
  bool get tagWrite;

  /// A built-in no saved profile overrides; it cannot be deleted.
  @BuiltValueField(wireName: r'builtIn')
  bool get builtIn;

  @BuiltValueField(wireName: r'sample')
  OrganizeSample get sample;

  @BuiltValueField(wireName: r'saved')
  OrganizeTemplates? get saved;

  OrganizeProfile._();

  factory OrganizeProfile([void updates(OrganizeProfileBuilder b)]) = _$OrganizeProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeProfile> get serializer => _$OrganizeProfileSerializer();
}

class _$OrganizeProfileSerializer implements PrimitiveSerializer<OrganizeProfile> {
  @override
  final Iterable<Type> types = const [OrganizeProfile, _$OrganizeProfile];

  @override
  final String wireName = r'OrganizeProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
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
    yield r'tagWrite';
    yield serializers.serialize(
      object.tagWrite,
      specifiedType: const FullType(bool),
    );
    yield r'builtIn';
    yield serializers.serialize(
      object.builtIn,
      specifiedType: const FullType(bool),
    );
    yield r'sample';
    yield serializers.serialize(
      object.sample,
      specifiedType: const FullType(OrganizeSample),
    );
    if (object.saved != null) {
      yield r'saved';
      yield serializers.serialize(
        object.saved,
        specifiedType: const FullType(OrganizeTemplates),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    OrganizeProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeProfileBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
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
        case r'tagWrite':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.tagWrite = valueDes;
          break;
        case r'builtIn':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.builtIn = valueDes;
          break;
        case r'sample':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(OrganizeSample),
          ) as OrganizeSample;
          result.sample.replace(valueDes);
          break;
        case r'saved':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(OrganizeTemplates),
          ) as OrganizeTemplates?;
          if (valueDes == null) continue;
          result.saved.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrganizeProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeProfileBuilder();
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


