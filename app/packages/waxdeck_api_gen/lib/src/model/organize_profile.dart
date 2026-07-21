//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_profile.g.dart';

/// One organize profile.
///
/// Properties:
/// * [name] - The profile name organize requests reference.
/// * [musicTemplate] - Path template for music, when set.
/// * [audiobookTemplate] - Path template for audiobooks, when set.
/// * [podcastTemplate] - Path template for podcast files, when set.
/// * [tagWrite] - Whether organizing also writes tags.
@BuiltValue()
abstract class OrganizeProfile implements Built<OrganizeProfile, OrganizeProfileBuilder> {
  /// The profile name organize requests reference.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Path template for music, when set.
  @BuiltValueField(wireName: r'musicTemplate')
  String? get musicTemplate;

  /// Path template for audiobooks, when set.
  @BuiltValueField(wireName: r'audiobookTemplate')
  String? get audiobookTemplate;

  /// Path template for podcast files, when set.
  @BuiltValueField(wireName: r'podcastTemplate')
  String? get podcastTemplate;

  /// Whether organizing also writes tags.
  @BuiltValueField(wireName: r'tagWrite')
  bool? get tagWrite;

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

