//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'play_state.g.dart';

/// The calling user's playback state for one item.
///
/// Properties:
/// * [pid] - The item this state belongs to.
/// * [positionMs] - Resume position in milliseconds. For multi-file audiobooks this is always a book-timeline position spanning all parts. 
/// * [played] - Whether the item has crossed its played threshold. The server derives this from the position reached against the item's full duration (per-medium thresholds), never from a listened-milliseconds ratio, so silence trimming and speed changes cannot distort it. 
/// * [finished] - Whether the item was completed. For multi-file audiobooks the server derives completion from the book-timeline position; a client-reported finished flag alone does not finish a book. 
/// * [playCount] - How many times the item has been played.
/// * [starred] - Whether the caller starred the item.
/// * [rating] - The caller's rating (0 to 100); absent or null when unrated.
/// * [updatedAt] - When this state last changed.
@BuiltValue()
abstract class PlayState implements Built<PlayState, PlayStateBuilder> {
  /// The item this state belongs to.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Resume position in milliseconds. For multi-file audiobooks this is always a book-timeline position spanning all parts. 
  @BuiltValueField(wireName: r'positionMs')
  int get positionMs;

  /// Whether the item has crossed its played threshold. The server derives this from the position reached against the item's full duration (per-medium thresholds), never from a listened-milliseconds ratio, so silence trimming and speed changes cannot distort it. 
  @BuiltValueField(wireName: r'played')
  bool get played;

  /// Whether the item was completed. For multi-file audiobooks the server derives completion from the book-timeline position; a client-reported finished flag alone does not finish a book. 
  @BuiltValueField(wireName: r'finished')
  bool get finished;

  /// How many times the item has been played.
  @BuiltValueField(wireName: r'playCount')
  int get playCount;

  /// Whether the caller starred the item.
  @BuiltValueField(wireName: r'starred')
  bool get starred;

  /// The caller's rating (0 to 100); absent or null when unrated.
  @BuiltValueField(wireName: r'rating')
  int? get rating;

  /// When this state last changed.
  @BuiltValueField(wireName: r'updatedAt')
  DateTime? get updatedAt;

  PlayState._();

  factory PlayState([void updates(PlayStateBuilder b)]) = _$PlayState;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlayStateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlayState> get serializer => _$PlayStateSerializer();
}

class _$PlayStateSerializer implements PrimitiveSerializer<PlayState> {
  @override
  final Iterable<Type> types = const [PlayState, _$PlayState];

  @override
  final String wireName = r'PlayState';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlayState object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'positionMs';
    yield serializers.serialize(
      object.positionMs,
      specifiedType: const FullType(int),
    );
    yield r'played';
    yield serializers.serialize(
      object.played,
      specifiedType: const FullType(bool),
    );
    yield r'finished';
    yield serializers.serialize(
      object.finished,
      specifiedType: const FullType(bool),
    );
    yield r'playCount';
    yield serializers.serialize(
      object.playCount,
      specifiedType: const FullType(int),
    );
    yield r'starred';
    yield serializers.serialize(
      object.starred,
      specifiedType: const FullType(bool),
    );
    if (object.rating != null) {
      yield r'rating';
      yield serializers.serialize(
        object.rating,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.updatedAt != null) {
      yield r'updatedAt';
      yield serializers.serialize(
        object.updatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlayState object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlayStateBuilder result,
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
        case r'positionMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.positionMs = valueDes;
          break;
        case r'played':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.played = valueDes;
          break;
        case r'finished':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.finished = valueDes;
          break;
        case r'playCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.playCount = valueDes;
          break;
        case r'starred':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.starred = valueDes;
          break;
        case r'rating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.rating = valueDes;
          break;
        case r'updatedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlayState deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlayStateBuilder();
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

