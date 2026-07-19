//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'radio_station_edit.g.dart';

/// Station fields for create and update.
///
/// Properties:
/// * [name] - Display name.
/// * [streamUrl] - The station's stream URL; http or https.
/// * [homepageUrl] - The station's website.
/// * [logoUrl] - Station logo URL.
@BuiltValue()
abstract class RadioStationEdit implements Built<RadioStationEdit, RadioStationEditBuilder> {
  /// Display name.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// The station's stream URL; http or https.
  @BuiltValueField(wireName: r'streamUrl')
  String get streamUrl;

  /// The station's website.
  @BuiltValueField(wireName: r'homepageUrl')
  String? get homepageUrl;

  /// Station logo URL.
  @BuiltValueField(wireName: r'logoUrl')
  String? get logoUrl;

  RadioStationEdit._();

  factory RadioStationEdit([void updates(RadioStationEditBuilder b)]) = _$RadioStationEdit;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RadioStationEditBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RadioStationEdit> get serializer => _$RadioStationEditSerializer();
}

class _$RadioStationEditSerializer implements PrimitiveSerializer<RadioStationEdit> {
  @override
  final Iterable<Type> types = const [RadioStationEdit, _$RadioStationEdit];

  @override
  final String wireName = r'RadioStationEdit';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RadioStationEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'streamUrl';
    yield serializers.serialize(
      object.streamUrl,
      specifiedType: const FullType(String),
    );
    if (object.homepageUrl != null) {
      yield r'homepageUrl';
      yield serializers.serialize(
        object.homepageUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.logoUrl != null) {
      yield r'logoUrl';
      yield serializers.serialize(
        object.logoUrl,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RadioStationEdit object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RadioStationEditBuilder result,
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
        case r'streamUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.streamUrl = valueDes;
          break;
        case r'homepageUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.homepageUrl = valueDes;
          break;
        case r'logoUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.logoUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RadioStationEdit deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RadioStationEditBuilder();
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

