//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/enrichment_cache_kind.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_cache_report.g.dart';

/// What the enrichment response cache holds.
///
/// Properties:
/// * [rows] - Cached answers held, the exempt ones included.
/// * [bytes] - What they cost.
/// * [oldestAt] - When the oldest cached answer was fetched. Absent when the cache is empty. 
/// * [newestAt] - When the newest cached answer was fetched. Absent when the cache is empty. 
/// * [kinds] - Per-kind breakdown, largest first.
/// * [exemptRows] - Rows a prune leaves alone: the Cover Art Archive's group records, facts about stored covers rather than cached answers. 
/// * [exemptBytes] - What those cost.
@BuiltValue()
abstract class EnrichmentCacheReport implements Built<EnrichmentCacheReport, EnrichmentCacheReportBuilder> {
  /// Cached answers held, the exempt ones included.
  @BuiltValueField(wireName: r'rows')
  int get rows;

  /// What they cost.
  @BuiltValueField(wireName: r'bytes')
  int get bytes;

  /// When the oldest cached answer was fetched. Absent when the cache is empty. 
  @BuiltValueField(wireName: r'oldestAt')
  DateTime? get oldestAt;

  /// When the newest cached answer was fetched. Absent when the cache is empty. 
  @BuiltValueField(wireName: r'newestAt')
  DateTime? get newestAt;

  /// Per-kind breakdown, largest first.
  @BuiltValueField(wireName: r'kinds')
  BuiltList<EnrichmentCacheKind> get kinds;

  /// Rows a prune leaves alone: the Cover Art Archive's group records, facts about stored covers rather than cached answers. 
  @BuiltValueField(wireName: r'exemptRows')
  int get exemptRows;

  /// What those cost.
  @BuiltValueField(wireName: r'exemptBytes')
  int get exemptBytes;

  EnrichmentCacheReport._();

  factory EnrichmentCacheReport([void updates(EnrichmentCacheReportBuilder b)]) = _$EnrichmentCacheReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentCacheReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentCacheReport> get serializer => _$EnrichmentCacheReportSerializer();
}

class _$EnrichmentCacheReportSerializer implements PrimitiveSerializer<EnrichmentCacheReport> {
  @override
  final Iterable<Type> types = const [EnrichmentCacheReport, _$EnrichmentCacheReport];

  @override
  final String wireName = r'EnrichmentCacheReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentCacheReport object, {
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
    yield r'kinds';
    yield serializers.serialize(
      object.kinds,
      specifiedType: const FullType(BuiltList, [FullType(EnrichmentCacheKind)]),
    );
    yield r'exemptRows';
    yield serializers.serialize(
      object.exemptRows,
      specifiedType: const FullType(int),
    );
    yield r'exemptBytes';
    yield serializers.serialize(
      object.exemptBytes,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentCacheReport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentCacheReportBuilder result,
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
        case r'oldestAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.oldestAt = valueDes;
          break;
        case r'newestAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.newestAt = valueDes;
          break;
        case r'kinds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EnrichmentCacheKind)]),
          ) as BuiltList<EnrichmentCacheKind>;
          result.kinds.replace(valueDes);
          break;
        case r'exemptRows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.exemptRows = valueDes;
          break;
        case r'exemptBytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.exemptBytes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentCacheReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentCacheReportBuilder();
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


