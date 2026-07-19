//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'radio_station.g.dart';

/// One internet radio station in the shared library.
///
/// Properties:
/// * [pid] - Type-prefixed ULID.
/// * [name] - Display name.
/// * [streamUrl] - The station's stream URL.
/// * [homepageUrl] - The station's website, when known.
/// * [logoUrl] - Station logo URL, when known. Clients fetch logos directly (they are not proxied), so an http logo may be blocked as mixed content on an https UI; render the placeholder in that case. 
/// * [createdAt] - When the station was added.
@BuiltValue()
abstract class RadioStation implements Built<RadioStation, RadioStationBuilder> {
  /// Type-prefixed ULID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Display name.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// The station's stream URL.
  @BuiltValueField(wireName: r'streamUrl')
  String get streamUrl;

  /// The station's website, when known.
  @BuiltValueField(wireName: r'homepageUrl')
  String? get homepageUrl;

  /// Station logo URL, when known. Clients fetch logos directly (they are not proxied), so an http logo may be blocked as mixed content on an https UI; render the placeholder in that case. 
  @BuiltValueField(wireName: r'logoUrl')
  String? get logoUrl;

  /// When the station was added.
  @BuiltValueField(wireName: r'createdAt')
  DateTime get createdAt;

  RadioStation._();

  factory RadioStation([void updates(RadioStationBuilder b)]) = _$RadioStation;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RadioStationBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RadioStation> get serializer => _$RadioStationSerializer();
}

class _$RadioStationSerializer implements PrimitiveSerializer<RadioStation> {
  @override
  final Iterable<Type> types = const [RadioStation, _$RadioStation];

  @override
  final String wireName = r'RadioStation';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RadioStation object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
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
    yield r'createdAt';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RadioStation object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RadioStationBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
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
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RadioStation deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RadioStationBuilder();
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

