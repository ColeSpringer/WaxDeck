//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enrichment_last_run.g.dart';

/// What the most recent finished whole-library pass did. Absent until one has finished.  Coverage answers how much of the library is enriched; this answers whether the last pass accomplished anything, which coverage cannot. A pass that searched two thousand albums and matched none leaves coverage exactly where it was, and so does one whose every tag write failed; both read as \"nothing happened\" without these counts. 
///
/// Properties:
/// * [albumsSearched] - Albums the release match looked up: which pressing of a record the library holds, resolved from a barcode or a catalog number. 
/// * [albumsMatched] - Albums it pinned to a release. Searched without matched is a library whose albums carry no identifiers, not a broken pass. 
/// * [tagsWritten] - Files the pass wrote enriched values back into. Zero unless tag write-back is on, which is what makes enrichment survive a rescan. 
/// * [tagsFailed] - Files whose write failed. The catalog kept the values either way.
/// * [tagsUnrepresented] - Files whose format cannot store a key that was filled. Not a failure: the bytes are unchanged and correct. 
/// * [tagsSkipped] - Book parts left unwritten because their book's primary part failed. 
/// * [finishedAt] - When the pass finished.
@BuiltValue()
abstract class EnrichmentLastRun implements Built<EnrichmentLastRun, EnrichmentLastRunBuilder> {
  /// Albums the release match looked up: which pressing of a record the library holds, resolved from a barcode or a catalog number. 
  @BuiltValueField(wireName: r'albumsSearched')
  int get albumsSearched;

  /// Albums it pinned to a release. Searched without matched is a library whose albums carry no identifiers, not a broken pass. 
  @BuiltValueField(wireName: r'albumsMatched')
  int get albumsMatched;

  /// Files the pass wrote enriched values back into. Zero unless tag write-back is on, which is what makes enrichment survive a rescan. 
  @BuiltValueField(wireName: r'tagsWritten')
  int get tagsWritten;

  /// Files whose write failed. The catalog kept the values either way.
  @BuiltValueField(wireName: r'tagsFailed')
  int get tagsFailed;

  /// Files whose format cannot store a key that was filled. Not a failure: the bytes are unchanged and correct. 
  @BuiltValueField(wireName: r'tagsUnrepresented')
  int get tagsUnrepresented;

  /// Book parts left unwritten because their book's primary part failed. 
  @BuiltValueField(wireName: r'tagsSkipped')
  int get tagsSkipped;

  /// When the pass finished.
  @BuiltValueField(wireName: r'finishedAt')
  DateTime? get finishedAt;

  EnrichmentLastRun._();

  factory EnrichmentLastRun([void updates(EnrichmentLastRunBuilder b)]) = _$EnrichmentLastRun;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnrichmentLastRunBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnrichmentLastRun> get serializer => _$EnrichmentLastRunSerializer();
}

class _$EnrichmentLastRunSerializer implements PrimitiveSerializer<EnrichmentLastRun> {
  @override
  final Iterable<Type> types = const [EnrichmentLastRun, _$EnrichmentLastRun];

  @override
  final String wireName = r'EnrichmentLastRun';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnrichmentLastRun object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'albumsSearched';
    yield serializers.serialize(
      object.albumsSearched,
      specifiedType: const FullType(int),
    );
    yield r'albumsMatched';
    yield serializers.serialize(
      object.albumsMatched,
      specifiedType: const FullType(int),
    );
    yield r'tagsWritten';
    yield serializers.serialize(
      object.tagsWritten,
      specifiedType: const FullType(int),
    );
    yield r'tagsFailed';
    yield serializers.serialize(
      object.tagsFailed,
      specifiedType: const FullType(int),
    );
    yield r'tagsUnrepresented';
    yield serializers.serialize(
      object.tagsUnrepresented,
      specifiedType: const FullType(int),
    );
    yield r'tagsSkipped';
    yield serializers.serialize(
      object.tagsSkipped,
      specifiedType: const FullType(int),
    );
    if (object.finishedAt != null) {
      yield r'finishedAt';
      yield serializers.serialize(
        object.finishedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EnrichmentLastRun object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnrichmentLastRunBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'albumsSearched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.albumsSearched = valueDes;
          break;
        case r'albumsMatched':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.albumsMatched = valueDes;
          break;
        case r'tagsWritten':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.tagsWritten = valueDes;
          break;
        case r'tagsFailed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.tagsFailed = valueDes;
          break;
        case r'tagsUnrepresented':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.tagsUnrepresented = valueDes;
          break;
        case r'tagsSkipped':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.tagsSkipped = valueDes;
          break;
        case r'finishedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.finishedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnrichmentLastRun deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnrichmentLastRunBuilder();
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

