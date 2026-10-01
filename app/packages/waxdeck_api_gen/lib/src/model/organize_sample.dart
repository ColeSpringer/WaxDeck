//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'organize_sample.g.dart';

/// Where a profile lays out a fixed sample track, book and episode; an empty path is a template that renders none for that sample. 
///
/// Properties:
/// * [music] 
/// * [audiobook] 
/// * [podcast] 
@BuiltValue()
abstract class OrganizeSample implements Built<OrganizeSample, OrganizeSampleBuilder> {
  @BuiltValueField(wireName: r'music')
  String get music;

  @BuiltValueField(wireName: r'audiobook')
  String get audiobook;

  @BuiltValueField(wireName: r'podcast')
  String get podcast;

  OrganizeSample._();

  factory OrganizeSample([void updates(OrganizeSampleBuilder b)]) = _$OrganizeSample;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OrganizeSampleBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OrganizeSample> get serializer => _$OrganizeSampleSerializer();
}

class _$OrganizeSampleSerializer implements PrimitiveSerializer<OrganizeSample> {
  @override
  final Iterable<Type> types = const [OrganizeSample, _$OrganizeSample];

  @override
  final String wireName = r'OrganizeSample';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OrganizeSample object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'music';
    yield serializers.serialize(
      object.music,
      specifiedType: const FullType(String),
    );
    yield r'audiobook';
    yield serializers.serialize(
      object.audiobook,
      specifiedType: const FullType(String),
    );
    yield r'podcast';
    yield serializers.serialize(
      object.podcast,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OrganizeSample object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OrganizeSampleBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'music':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.music = valueDes;
          break;
        case r'audiobook':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.audiobook = valueDes;
          break;
        case r'podcast':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.podcast = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OrganizeSample deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OrganizeSampleBuilder();
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


