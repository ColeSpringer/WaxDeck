//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/thumbnail_rung.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'thumbnail_cache_report.g.dart';

/// What the generated thumbnail cache holds, and what the source images behind it cost. 
///
/// Properties:
/// * [rows] - Cached thumbnails held.
/// * [bytes] - What those thumbnails cost.
/// * [sources] - Source images with at least one derivative, out of `artSources`. 
/// * [artSources] - Source images held.
/// * [artSourceBytes] - What those originals cost. The figure `bytes` is read against: a cache smaller than its own sources is doing its job. 
/// * [oldestAt] - When the oldest cached thumbnail was generated. Absent when the cache is empty. 
/// * [newestAt] - When the newest cached thumbnail was generated. Absent when the cache is empty. 
/// * [rungs] - Per-rung breakdown, largest box first.
@BuiltValue()
abstract class ThumbnailCacheReport implements Built<ThumbnailCacheReport, ThumbnailCacheReportBuilder> {
  /// Cached thumbnails held.
  @BuiltValueField(wireName: r'rows')
  int get rows;

  /// What those thumbnails cost.
  @BuiltValueField(wireName: r'bytes')
  int get bytes;

  /// Source images with at least one derivative, out of `artSources`. 
  @BuiltValueField(wireName: r'sources')
  int get sources;

  /// Source images held.
  @BuiltValueField(wireName: r'artSources')
  int get artSources;

  /// What those originals cost. The figure `bytes` is read against: a cache smaller than its own sources is doing its job. 
  @BuiltValueField(wireName: r'artSourceBytes')
  int get artSourceBytes;

  /// When the oldest cached thumbnail was generated. Absent when the cache is empty. 
  @BuiltValueField(wireName: r'oldestAt')
  DateTime? get oldestAt;

  /// When the newest cached thumbnail was generated. Absent when the cache is empty. 
  @BuiltValueField(wireName: r'newestAt')
  DateTime? get newestAt;

  /// Per-rung breakdown, largest box first.
  @BuiltValueField(wireName: r'rungs')
  BuiltList<ThumbnailRung> get rungs;

  ThumbnailCacheReport._();

  factory ThumbnailCacheReport([void updates(ThumbnailCacheReportBuilder b)]) = _$ThumbnailCacheReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ThumbnailCacheReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ThumbnailCacheReport> get serializer => _$ThumbnailCacheReportSerializer();
}

class _$ThumbnailCacheReportSerializer implements PrimitiveSerializer<ThumbnailCacheReport> {
  @override
  final Iterable<Type> types = const [ThumbnailCacheReport, _$ThumbnailCacheReport];

  @override
  final String wireName = r'ThumbnailCacheReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ThumbnailCacheReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'rows';
    yield serializers.serialize(
      object.rows,
      specifiedType: const FullType(int),
    );
    yield r'bytes';
    yield serializers.serialize(
      object.bytes,
      specifiedType: const FullType(int),
    );
    yield r'sources';
    yield serializers.serialize(
      object.sources,
      specifiedType: const FullType(int),
    );
    yield r'artSources';
    yield serializers.serialize(
      object.artSources,
      specifiedType: const FullType(int),
    );
    yield r'artSourceBytes';
    yield serializers.serialize(
      object.artSourceBytes,
      specifiedType: const FullType(int),
    );
    if (object.oldestAt != null) {
      yield r'oldestAt';
      yield serializers.serialize(
        object.oldestAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.newestAt != null) {
      yield r'newestAt';
      yield serializers.serialize(
        object.newestAt,
        specifiedType: const FullType(DateTime),
      );
    }
    yield r'rungs';
    yield serializers.serialize(
      object.rungs,
      specifiedType: const FullType(BuiltList, [FullType(ThumbnailRung)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ThumbnailCacheReport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ThumbnailCacheReportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'rows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.rows = valueDes;
          break;
        case r'bytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bytes = valueDes;
          break;
        case r'sources':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sources = valueDes;
          break;
        case r'artSources':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.artSources = valueDes;
          break;
        case r'artSourceBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.artSourceBytes = valueDes;
          break;
        case r'oldestAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.oldestAt = valueDes;
          break;
        case r'newestAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.newestAt = valueDes;
          break;
        case r'rungs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ThumbnailRung)]),
          ) as BuiltList<ThumbnailRung>;
          result.rungs.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ThumbnailCacheReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ThumbnailCacheReportBuilder();
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

