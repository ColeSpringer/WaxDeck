//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/top_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'server_year_in_review.g.dart';

/// The whole server's listening recap for one calendar year, aggregated across users who have not opted out of shared stats. Each participant's listening is bucketed in their own timezone. 
///
/// Properties:
/// * [year] - The calendar year.
/// * [participants] - Users whose listening is included (those who have not opted out and listened that year). 
/// * [totalMs] - Total milliseconds listened across participants.
/// * [sessions] - Listen sessions across participants.
/// * [topArtists] - The server's most-listened music artists that year.
/// * [topTracks] - The server's most-listened tracks that year.
/// * [topGenres] - The server's most-listened music genres that year.
@BuiltValue()
abstract class ServerYearInReview implements Built<ServerYearInReview, ServerYearInReviewBuilder> {
  /// The calendar year.
  @BuiltValueField(wireName: r'year')
  int get year;

  /// Users whose listening is included (those who have not opted out and listened that year). 
  @BuiltValueField(wireName: r'participants')
  int get participants;

  /// Total milliseconds listened across participants.
  @BuiltValueField(wireName: r'totalMs')
  int get totalMs;

  /// Listen sessions across participants.
  @BuiltValueField(wireName: r'sessions')
  int get sessions;

  /// The server's most-listened music artists that year.
  @BuiltValueField(wireName: r'topArtists')
  BuiltList<TopEntry> get topArtists;

  /// The server's most-listened tracks that year.
  @BuiltValueField(wireName: r'topTracks')
  BuiltList<TopEntry> get topTracks;

  /// The server's most-listened music genres that year.
  @BuiltValueField(wireName: r'topGenres')
  BuiltList<TopEntry> get topGenres;

  ServerYearInReview._();

  factory ServerYearInReview([void updates(ServerYearInReviewBuilder b)]) = _$ServerYearInReview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServerYearInReviewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServerYearInReview> get serializer => _$ServerYearInReviewSerializer();
}

class _$ServerYearInReviewSerializer implements PrimitiveSerializer<ServerYearInReview> {
  @override
  final Iterable<Type> types = const [ServerYearInReview, _$ServerYearInReview];

  @override
  final String wireName = r'ServerYearInReview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServerYearInReview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'year';
    yield serializers.serialize(
      object.year,
      specifiedType: const FullType(int),
    );
    yield r'participants';
    yield serializers.serialize(
      object.participants,
      specifiedType: const FullType(int),
    );
    yield r'totalMs';
    yield serializers.serialize(
      object.totalMs,
      specifiedType: const FullType(int),
    );
    yield r'sessions';
    yield serializers.serialize(
      object.sessions,
      specifiedType: const FullType(int),
    );
    yield r'topArtists';
    yield serializers.serialize(
      object.topArtists,
      specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
    );
    yield r'topTracks';
    yield serializers.serialize(
      object.topTracks,
      specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
    );
    yield r'topGenres';
    yield serializers.serialize(
      object.topGenres,
      specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ServerYearInReview object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ServerYearInReviewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'year':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.year = valueDes;
          break;
        case r'participants':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.participants = valueDes;
          break;
        case r'totalMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalMs = valueDes;
          break;
        case r'sessions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sessions = valueDes;
          break;
        case r'topArtists':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
          ) as BuiltList<TopEntry>;
          result.topArtists.replace(valueDes);
          break;
        case r'topTracks':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
          ) as BuiltList<TopEntry>;
          result.topTracks.replace(valueDes);
          break;
        case r'topGenres':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(TopEntry)]),
          ) as BuiltList<TopEntry>;
          result.topGenres.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServerYearInReview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServerYearInReviewBuilder();
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

