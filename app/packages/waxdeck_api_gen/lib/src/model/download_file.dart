//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'download_file.g.dart';

/// One downloadable backing file of an item.
///
/// Properties:
/// * [url] - Origin-relative, media-token-authenticated download URL serving this file's original bytes with range support. 
/// * [mimeType] - MIME type of the file.
/// * [sizeBytes] - Exact size of the file in bytes.
/// * [durationMs] - This file's own duration in milliseconds, absent when the catalog does not know it (a file no scan could probe). It is the file's duration, not the item's, and the two differ in both directions: each part of a multi-file audiobook reports its own, so a client holding the downloaded parts can place a book-timeline position in one of them without asking the server; and an item carved out of a larger file reports the containing file's duration, with `spanStartMs` and `spanEndMs` giving the item's window inside it. 
/// * [fileName] - Suggested file name (the original base name), also sent as the download's `Content-Disposition`. 
/// * [essenceHash] - Content hash of the file's audio essence, stable across retags and moves: the download-store key. 
/// * [etag] - Strong validator of the exact file bytes, served as the download's `ETag`. Changes on any rewrite of the file, including retags that leave `essenceHash` unchanged; a mismatch means restart this file's transfer instead of resuming a range. 
@BuiltValue()
abstract class DownloadFile implements Built<DownloadFile, DownloadFileBuilder> {
  /// Origin-relative, media-token-authenticated download URL serving this file's original bytes with range support. 
  @BuiltValueField(wireName: r'url')
  String get url;

  /// MIME type of the file.
  @BuiltValueField(wireName: r'mimeType')
  String get mimeType;

  /// Exact size of the file in bytes.
  @BuiltValueField(wireName: r'sizeBytes')
  int get sizeBytes;

  /// This file's own duration in milliseconds, absent when the catalog does not know it (a file no scan could probe). It is the file's duration, not the item's, and the two differ in both directions: each part of a multi-file audiobook reports its own, so a client holding the downloaded parts can place a book-timeline position in one of them without asking the server; and an item carved out of a larger file reports the containing file's duration, with `spanStartMs` and `spanEndMs` giving the item's window inside it. 
  @BuiltValueField(wireName: r'durationMs')
  int? get durationMs;

  /// Suggested file name (the original base name), also sent as the download's `Content-Disposition`. 
  @BuiltValueField(wireName: r'fileName')
  String get fileName;

  /// Content hash of the file's audio essence, stable across retags and moves: the download-store key. 
  @BuiltValueField(wireName: r'essenceHash')
  String get essenceHash;

  /// Strong validator of the exact file bytes, served as the download's `ETag`. Changes on any rewrite of the file, including retags that leave `essenceHash` unchanged; a mismatch means restart this file's transfer instead of resuming a range. 
  @BuiltValueField(wireName: r'etag')
  String get etag;

  DownloadFile._();

  factory DownloadFile([void updates(DownloadFileBuilder b)]) = _$DownloadFile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DownloadFileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DownloadFile> get serializer => _$DownloadFileSerializer();
}

class _$DownloadFileSerializer implements PrimitiveSerializer<DownloadFile> {
  @override
  final Iterable<Type> types = const [DownloadFile, _$DownloadFile];

  @override
  final String wireName = r'DownloadFile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DownloadFile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'url';
    yield serializers.serialize(
      object.url,
      specifiedType: const FullType(String),
    );
    yield r'mimeType';
    yield serializers.serialize(
      object.mimeType,
      specifiedType: const FullType(String),
    );
    yield r'sizeBytes';
    yield serializers.serialize(
      object.sizeBytes,
      specifiedType: const FullType(int),
    );
    if (object.durationMs != null) {
      yield r'durationMs';
      yield serializers.serialize(
        object.durationMs,
        specifiedType: const FullType(int),
      );
    }
    yield r'fileName';
    yield serializers.serialize(
      object.fileName,
      specifiedType: const FullType(String),
    );
    yield r'essenceHash';
    yield serializers.serialize(
      object.essenceHash,
      specifiedType: const FullType(String),
    );
    yield r'etag';
    yield serializers.serialize(
      object.etag,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DownloadFile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DownloadFileBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'mimeType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mimeType = valueDes;
          break;
        case r'sizeBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sizeBytes = valueDes;
          break;
        case r'durationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMs = valueDes;
          break;
        case r'fileName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fileName = valueDes;
          break;
        case r'essenceHash':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.essenceHash = valueDes;
          break;
        case r'etag':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.etag = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DownloadFile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DownloadFileBuilder();
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

