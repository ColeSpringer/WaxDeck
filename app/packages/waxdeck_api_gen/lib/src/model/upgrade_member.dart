//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upgrade_member.g.dart';

/// One encoding of a recording.
///
/// Properties:
/// * [itemPid] - The item.
/// * [title] - Its title.
/// * [artist] - Its artist.
/// * [codec] - Audio codec.
/// * [bitrate] - Bitrate in bits per second, 0 when unknown.
/// * [sampleRate] - Sample rate in Hz, 0 when unknown.
/// * [bitDepth] - Bit depth, 0 when unknown or lossy.
/// * [lossless] - Whether the encoding is lossless.
/// * [best] - The group's suggested keeper.
@BuiltValue()
abstract class UpgradeMember implements Built<UpgradeMember, UpgradeMemberBuilder> {
  /// The item.
  @BuiltValueField(wireName: r'itemPid')
  String get itemPid;

  /// Its title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Its artist.
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// Audio codec.
  @BuiltValueField(wireName: r'codec')
  String get codec;

  /// Bitrate in bits per second, 0 when unknown.
  @BuiltValueField(wireName: r'bitrate')
  int? get bitrate;

  /// Sample rate in Hz, 0 when unknown.
  @BuiltValueField(wireName: r'sampleRate')
  int? get sampleRate;

  /// Bit depth, 0 when unknown or lossy.
  @BuiltValueField(wireName: r'bitDepth')
  int? get bitDepth;

  /// Whether the encoding is lossless.
  @BuiltValueField(wireName: r'lossless')
  bool get lossless;

  /// The group's suggested keeper.
  @BuiltValueField(wireName: r'best')
  bool get best;

  UpgradeMember._();

  factory UpgradeMember([void updates(UpgradeMemberBuilder b)]) = _$UpgradeMember;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpgradeMemberBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpgradeMember> get serializer => _$UpgradeMemberSerializer();
}

class _$UpgradeMemberSerializer implements PrimitiveSerializer<UpgradeMember> {
  @override
  final Iterable<Type> types = const [UpgradeMember, _$UpgradeMember];

  @override
  final String wireName = r'UpgradeMember';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpgradeMember object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'itemPid';
    yield serializers.serialize(
      object.itemPid,
      specifiedType: const FullType(String),
    );
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.artist != null) {
      yield r'artist';
      yield serializers.serialize(
        object.artist,
        specifiedType: const FullType(String),
      );
    }
    yield r'codec';
    yield serializers.serialize(
      object.codec,
      specifiedType: const FullType(String),
    );
    if (object.bitrate != null) {
      yield r'bitrate';
      yield serializers.serialize(
        object.bitrate,
        specifiedType: const FullType(int),
      );
    }
    if (object.sampleRate != null) {
      yield r'sampleRate';
      yield serializers.serialize(
        object.sampleRate,
        specifiedType: const FullType(int),
      );
    }
    if (object.bitDepth != null) {
      yield r'bitDepth';
      yield serializers.serialize(
        object.bitDepth,
        specifiedType: const FullType(int),
      );
    }
    yield r'lossless';
    yield serializers.serialize(
      object.lossless,
      specifiedType: const FullType(bool),
    );
    yield r'best';
    yield serializers.serialize(
      object.best,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UpgradeMember object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpgradeMemberBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'itemPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.itemPid = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'artist':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artist = valueDes;
          break;
        case r'codec':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.codec = valueDes;
          break;
        case r'bitrate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bitrate = valueDes;
          break;
        case r'sampleRate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sampleRate = valueDes;
          break;
        case r'bitDepth':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bitDepth = valueDes;
          break;
        case r'lossless':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.lossless = valueDes;
          break;
        case r'best':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.best = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpgradeMember deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpgradeMemberBuilder();
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

