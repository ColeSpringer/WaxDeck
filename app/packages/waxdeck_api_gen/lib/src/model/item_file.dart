//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'item_file.g.dart';

/// One file behind an item.
///
/// Properties:
/// * [filePid] - The file.
/// * [role] - `primary` (the file the item's details come from), `part` (a book's other files) or `alternate` (a copy); new roles may appear. 
/// * [name] - The file's name, without its folder.
/// * [path] - The file's path on the server. Administrators only.
/// * [sizeBytes] - The file's size in bytes, when it could be read.
/// * [codec] 
/// * [container] 
/// * [bitrate] - Bitrate in kilobits per second, when known.
/// * [sampleRate] - Sample rate in Hz, when known.
/// * [bitDepth] - Bits per sample of a lossless file, when known.
/// * [durationMs] - The file's length in milliseconds, when known.
/// * [libraryPid] - The library the file sits in, which for a copy can differ from the item's. 
/// * [reason] - Why a copy is one: `same-audio` (the same audio as one of the item's files) or `other-encoding` (another encoding of its recording). Copies only; new reasons may appear. 
@BuiltValue()
abstract class ItemFile implements Built<ItemFile, ItemFileBuilder> {
  /// The file.
  @BuiltValueField(wireName: r'filePid')
  String get filePid;

  /// `primary` (the file the item's details come from), `part` (a book's other files) or `alternate` (a copy); new roles may appear. 
  @BuiltValueField(wireName: r'role')
  String get role;

  /// The file's name, without its folder.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// The file's path on the server. Administrators only.
  @BuiltValueField(wireName: r'path')
  String? get path;

  /// The file's size in bytes, when it could be read.
  @BuiltValueField(wireName: r'sizeBytes')
  int? get sizeBytes;

  @BuiltValueField(wireName: r'codec')
  String? get codec;

  @BuiltValueField(wireName: r'container')
  String? get container;

  /// Bitrate in kilobits per second, when known.
  @BuiltValueField(wireName: r'bitrate')
  int? get bitrate;

  /// Sample rate in Hz, when known.
  @BuiltValueField(wireName: r'sampleRate')
  int? get sampleRate;

  /// Bits per sample of a lossless file, when known.
  @BuiltValueField(wireName: r'bitDepth')
  int? get bitDepth;

  /// The file's length in milliseconds, when known.
  @BuiltValueField(wireName: r'durationMs')
  int? get durationMs;

  /// The library the file sits in, which for a copy can differ from the item's. 
  @BuiltValueField(wireName: r'libraryPid')
  String? get libraryPid;

  /// Why a copy is one: `same-audio` (the same audio as one of the item's files) or `other-encoding` (another encoding of its recording). Copies only; new reasons may appear. 
  @BuiltValueField(wireName: r'reason')
  String? get reason;

  ItemFile._();

  factory ItemFile([void updates(ItemFileBuilder b)]) = _$ItemFile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ItemFileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ItemFile> get serializer => _$ItemFileSerializer();
}

class _$ItemFileSerializer implements PrimitiveSerializer<ItemFile> {
  @override
  final Iterable<Type> types = const [ItemFile, _$ItemFile];

  @override
  final String wireName = r'ItemFile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ItemFile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'filePid';
    yield serializers.serialize(
      object.filePid,
      specifiedType: const FullType(String),
    );
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.path != null) {
      yield r'path';
      yield serializers.serialize(
        object.path,
        specifiedType: const FullType(String),
      );
    }
    if (object.sizeBytes != null) {
      yield r'sizeBytes';
      yield serializers.serialize(
        object.sizeBytes,
        specifiedType: const FullType(int),
      );
    }
    if (object.codec != null) {
      yield r'codec';
      yield serializers.serialize(
        object.codec,
        specifiedType: const FullType(String),
      );
    }
    if (object.container != null) {
      yield r'container';
      yield serializers.serialize(
        object.container,
        specifiedType: const FullType(String),
      );
    }
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
    if (object.durationMs != null) {
      yield r'durationMs';
      yield serializers.serialize(
        object.durationMs,
        specifiedType: const FullType(int),
      );
    }
    if (object.libraryPid != null) {
      yield r'libraryPid';
      yield serializers.serialize(
        object.libraryPid,
        specifiedType: const FullType(String),
      );
    }
    if (object.reason != null) {
      yield r'reason';
      yield serializers.serialize(
        object.reason,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ItemFile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ItemFileBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'filePid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.filePid = valueDes;
          break;
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.role = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.path = valueDes;
          break;
        case r'sizeBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.sizeBytes = valueDes;
          break;
        case r'codec':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.codec = valueDes;
          break;
        case r'container':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.container = valueDes;
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
        case r'durationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.durationMs = valueDes;
          break;
        case r'libraryPid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.libraryPid = valueDes;
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.reason = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ItemFile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ItemFileBuilder();
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


