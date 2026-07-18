//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/download_file.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'download_info.g.dart';

/// Everything a client needs to download one item's original bytes.
///
/// Properties:
/// * [pid] - The resolved item's PID.
/// * [files] - The item's backing files in playback order. One entry for a track or single-file book; one per part for a multi-file audiobook; exactly one (the containing file) for an item carved out of a larger file. 
/// * [spanStartMs] - Start of the item's playback window within its single backing file, in milliseconds. Present only for items carved out of a larger file (CUE-backed virtual tracks); offline playback plays the window, not the whole file. 
/// * [spanEndMs] - End of the playback window in milliseconds, exclusive. Present exactly when `spanStartMs` is. 
/// * [expiresAt] - When the embedded media tokens stop being accepted.
@BuiltValue()
abstract class DownloadInfo implements Built<DownloadInfo, DownloadInfoBuilder> {
  /// The resolved item's PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// The item's backing files in playback order. One entry for a track or single-file book; one per part for a multi-file audiobook; exactly one (the containing file) for an item carved out of a larger file. 
  @BuiltValueField(wireName: r'files')
  BuiltList<DownloadFile> get files;

  /// Start of the item's playback window within its single backing file, in milliseconds. Present only for items carved out of a larger file (CUE-backed virtual tracks); offline playback plays the window, not the whole file. 
  @BuiltValueField(wireName: r'spanStartMs')
  int? get spanStartMs;

  /// End of the playback window in milliseconds, exclusive. Present exactly when `spanStartMs` is. 
  @BuiltValueField(wireName: r'spanEndMs')
  int? get spanEndMs;

  /// When the embedded media tokens stop being accepted.
  @BuiltValueField(wireName: r'expiresAt')
  DateTime get expiresAt;

  DownloadInfo._();

  factory DownloadInfo([void updates(DownloadInfoBuilder b)]) = _$DownloadInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DownloadInfoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DownloadInfo> get serializer => _$DownloadInfoSerializer();
}

class _$DownloadInfoSerializer implements PrimitiveSerializer<DownloadInfo> {
  @override
  final Iterable<Type> types = const [DownloadInfo, _$DownloadInfo];

  @override
  final String wireName = r'DownloadInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DownloadInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'files';
    yield serializers.serialize(
      object.files,
      specifiedType: const FullType(BuiltList, [FullType(DownloadFile)]),
    );
    if (object.spanStartMs != null) {
      yield r'spanStartMs';
      yield serializers.serialize(
        object.spanStartMs,
        specifiedType: const FullType(int),
      );
    }
    if (object.spanEndMs != null) {
      yield r'spanEndMs';
      yield serializers.serialize(
        object.spanEndMs,
        specifiedType: const FullType(int),
      );
    }
    yield r'expiresAt';
    yield serializers.serialize(
      object.expiresAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DownloadInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DownloadInfoBuilder result,
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
        case r'files':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DownloadFile)]),
          ) as BuiltList<DownloadFile>;
          result.files.replace(valueDes);
          break;
        case r'spanStartMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.spanStartMs = valueDes;
          break;
        case r'spanEndMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.spanEndMs = valueDes;
          break;
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DownloadInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DownloadInfoBuilder();
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

