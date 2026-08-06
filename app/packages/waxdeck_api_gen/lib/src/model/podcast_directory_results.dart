//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/podcast_directory_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'podcast_directory_results.g.dart';

/// Podcast directory matches.
///
/// Properties:
/// * [entries] - Matches, best first.
@BuiltValue()
abstract class PodcastDirectoryResults implements Built<PodcastDirectoryResults, PodcastDirectoryResultsBuilder> {
  /// Matches, best first.
  @BuiltValueField(wireName: r'entries')
  BuiltList<PodcastDirectoryEntry> get entries;

  PodcastDirectoryResults._();

  factory PodcastDirectoryResults([void updates(PodcastDirectoryResultsBuilder b)]) = _$PodcastDirectoryResults;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PodcastDirectoryResultsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PodcastDirectoryResults> get serializer => _$PodcastDirectoryResultsSerializer();
}

class _$PodcastDirectoryResultsSerializer implements PrimitiveSerializer<PodcastDirectoryResults> {
  @override
  final Iterable<Type> types = const [PodcastDirectoryResults, _$PodcastDirectoryResults];

  @override
  final String wireName = r'PodcastDirectoryResults';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PodcastDirectoryResults object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType: const FullType(BuiltList, [FullType(PodcastDirectoryEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PodcastDirectoryResults object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PodcastDirectoryResultsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PodcastDirectoryEntry)]),
          ) as BuiltList<PodcastDirectoryEntry>;
          result.entries.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PodcastDirectoryResults deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PodcastDirectoryResultsBuilder();
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

