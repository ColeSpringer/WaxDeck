//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'radio_directory_entry.g.dart';

/// One station directory match.
///
/// Properties:
/// * [name] - Station name as listed in the directory.
/// * [streamUrl] - Resolved stream URL.
/// * [homepageUrl] - Station website.
/// * [logoUrl] - Station logo URL as the directory lists it, carried so adding the station keeps it. There is no proxy for a directory match: the proxy addresses a station by pid and a match has none until it is added, so a search result draws a monogram disc and the logo appears once the station is in the library. 
/// * [tags] - Comma-separated directory tags.
/// * [country] - Directory country name.
/// * [codec] - Directory-reported stream codec.
/// * [bitrateKbps] - Directory-reported bitrate in kbit/s, 0 when unknown.
@BuiltValue()
abstract class RadioDirectoryEntry implements Built<RadioDirectoryEntry, RadioDirectoryEntryBuilder> {
  /// Station name as listed in the directory.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Resolved stream URL.
  @BuiltValueField(wireName: r'streamUrl')
  String get streamUrl;

  /// Station website.
  @BuiltValueField(wireName: r'homepageUrl')
  String? get homepageUrl;

  /// Station logo URL as the directory lists it, carried so adding the station keeps it. There is no proxy for a directory match: the proxy addresses a station by pid and a match has none until it is added, so a search result draws a monogram disc and the logo appears once the station is in the library. 
  @BuiltValueField(wireName: r'logoUrl')
  String? get logoUrl;

  /// Comma-separated directory tags.
  @BuiltValueField(wireName: r'tags')
  String? get tags;

  /// Directory country name.
  @BuiltValueField(wireName: r'country')
  String? get country;

  /// Directory-reported stream codec.
  @BuiltValueField(wireName: r'codec')
  String? get codec;

  /// Directory-reported bitrate in kbit/s, 0 when unknown.
  @BuiltValueField(wireName: r'bitrateKbps')
  int? get bitrateKbps;

  RadioDirectoryEntry._();

  factory RadioDirectoryEntry([void updates(RadioDirectoryEntryBuilder b)]) = _$RadioDirectoryEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RadioDirectoryEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RadioDirectoryEntry> get serializer => _$RadioDirectoryEntrySerializer();
}

class _$RadioDirectoryEntrySerializer implements PrimitiveSerializer<RadioDirectoryEntry> {
  @override
  final Iterable<Type> types = const [RadioDirectoryEntry, _$RadioDirectoryEntry];

  @override
  final String wireName = r'RadioDirectoryEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RadioDirectoryEntry object, {
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
    if (object.tags != null) {
      yield r'tags';
      yield serializers.serialize(
        object.tags,
        specifiedType: const FullType(String),
      );
    }
    if (object.country != null) {
      yield r'country';
      yield serializers.serialize(
        object.country,
        specifiedType: const FullType(String),
      );
    }
    if (object.codec != null) {
      yield r'codec';
      yield serializers.serialize(
        object.codec,
        specifiedType: const FullType(String),
      );
    }
    if (object.bitrateKbps != null) {
      yield r'bitrateKbps';
      yield serializers.serialize(
        object.bitrateKbps,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RadioDirectoryEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RadioDirectoryEntryBuilder result,
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
        case r'tags':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.tags = valueDes;
          break;
        case r'country':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.country = valueDes;
          break;
        case r'codec':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.codec = valueDes;
          break;
        case r'bitrateKbps':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bitrateKbps = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RadioDirectoryEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RadioDirectoryEntryBuilder();
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

