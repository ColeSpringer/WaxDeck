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
/// * [filePid] - The file this encoding is, as getItemFiles names it. Within one item it is what tells the members apart. 
/// * [path] - The file's path on the server, given where another member of the group has the same codec and bitrate: there its file's name is what tells the two apart. 
/// * [title] - Its title.
/// * [artist] - Its artist.
/// * [codec] - Audio codec.
/// * [bitrate] - Bitrate in kilobits per second; absent when unknown.
/// * [sampleRate] - Sample rate in Hz; absent when unknown.
/// * [bitDepth] - Bit depth; absent when unknown or lossy.
/// * [lossless] - Whether the encoding is lossless.
/// * [best] - The group's suggested keeper.
@BuiltValue()
abstract class UpgradeMember implements Built<UpgradeMember, UpgradeMemberBuilder> {
  /// The item.
  @BuiltValueField(wireName: r'itemPid')
  String get itemPid;

  /// The file this encoding is, as getItemFiles names it. Within one item it is what tells the members apart. 
  @BuiltValueField(wireName: r'filePid')
  String get filePid;

  /// The file's path on the server, given where another member of the group has the same codec and bitrate: there its file's name is what tells the two apart. 
  @BuiltValueField(wireName: r'path')
  String? get path;

  /// Its title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Its artist.
  @BuiltValueField(wireName: r'artist')
  String? get artist;

  /// Audio codec.
  @BuiltValueField(wireName: r'codec')
  String get codec;

  /// Bitrate in kilobits per second; absent when unknown.
  @BuiltValueField(wireName: r'bitrate')
  int? get bitrate;

  /// Sample rate in Hz; absent when unknown.
  @BuiltValueField(wireName: r'sampleRate')
  int? get sampleRate;

  /// Bit depth; absent when unknown or lossy.
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
    yield r'filePid';
    yield serializers.serialize(
      object.filePid,
      specifiedType: const FullType(String),
    );
    if (object.path != null) {
      yield r'path';
      yield serializers.serialize(
        object.path,
        specifiedType: const FullType(String),
      );
    }
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
        case r'filePid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.filePid = valueDes;
          break;
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.path = valueDes;
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
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
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
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.bitrate = valueDes;
          break;
        case r'sampleRate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.sampleRate = valueDes;
          break;
        case r'bitDepth':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
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


