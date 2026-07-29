//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'episode_filter.g.dart';

/// Which new episodes auto-download takes, matched by keyword against the episode title. Terms are matched case-insensitively as substrings; an empty or absent `include` admits every episode, and `exclude` wins over `include` where both match. Titles only. Descriptions and summaries are deliberately not matched: feed descriptions carry sponsor copy, show boilerplate, and in some feeds full transcripts, so a term matched against them fires on episodes a listener would never call a match and the behaviour stops being predictable from the row the user is looking at. A filter applies to future arrivals only. Editing it does not re-evaluate the backlog and does not unqueue or remove anything already fetched: it is a subscription policy going forward, not a query over history. It is consulted only where auto-download decides what a feed refresh just added, so `autoDownload` must be on for it to do anything, and a manual fetch is never filtered. The effective policy for a show is the union across its subscribers, matching retention: an episode is fetched when any subscriber with auto-download on has a filter that admits it. 
///
/// Properties:
/// * [include] - Take an episode only when its title contains one of these terms. Empty or absent takes every episode. 
/// * [exclude] - Skip an episode whose title contains one of these terms, even when `include` matched it. 
@BuiltValue()
abstract class EpisodeFilter implements Built<EpisodeFilter, EpisodeFilterBuilder> {
  /// Take an episode only when its title contains one of these terms. Empty or absent takes every episode. 
  @BuiltValueField(wireName: r'include')
  BuiltList<String>? get include;

  /// Skip an episode whose title contains one of these terms, even when `include` matched it. 
  @BuiltValueField(wireName: r'exclude')
  BuiltList<String>? get exclude;

  EpisodeFilter._();

  factory EpisodeFilter([void updates(EpisodeFilterBuilder b)]) = _$EpisodeFilter;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EpisodeFilterBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EpisodeFilter> get serializer => _$EpisodeFilterSerializer();
}

class _$EpisodeFilterSerializer implements PrimitiveSerializer<EpisodeFilter> {
  @override
  final Iterable<Type> types = const [EpisodeFilter, _$EpisodeFilter];

  @override
  final String wireName = r'EpisodeFilter';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EpisodeFilter object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.include != null) {
      yield r'include';
      yield serializers.serialize(
        object.include,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.exclude != null) {
      yield r'exclude';
      yield serializers.serialize(
        object.exclude,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EpisodeFilter object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EpisodeFilterBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'include':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.include.replace(valueDes);
          break;
        case r'exclude':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.exclude.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EpisodeFilter deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EpisodeFilterBuilder();
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

